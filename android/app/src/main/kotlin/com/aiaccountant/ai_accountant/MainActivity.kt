package com.aiaccountant.ai_accountant

import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.Locale

class MainActivity : FlutterActivity() {
  private val tag = "AIWTNativeSpeech"
  private val channelName = "com.aiaccounting/native_speech"
  private val speechTimeoutMs = 12000L
  private val pcmSampleRate = 16000

  private var recognitionResult: MethodChannel.Result? = null
  private var speechRecognizer: SpeechRecognizer? = null
  @Volatile private var isPcmRecording = false
  private var audioRecord: AudioRecord? = null
  private var audioThread: Thread? = null
  private var audioBuffer: ByteArrayOutputStream? = null
  private val mainHandler = Handler(Looper.getMainLooper())
  private val timeoutRunnable = Runnable {
    finishSpeechRecognition("")
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    registerFlavorAdBridge(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "startSpeechRecognition" -> startSpeechRecognition(call, result)
          "stopSpeechRecognition" -> {
            stopSpeechRecognition()
            result.success(null)
          }
          "startPcmRecording" -> {
            startPcmRecording(result)
          }
          "stopPcmRecording" -> {
            result.success(stopPcmRecording())
          }
          "isSpeechRecognitionAvailable" -> result.success(isSpeechRecognitionAvailable())
          else -> result.notImplemented()
        }
      }
  }

  private fun registerFlavorAdBridge(flutterEngine: FlutterEngine) {
    try {
      val registrar = Class.forName("com.aiaccountant.ai_accountant.PangleAdsRegistrar")
      registrar
        .getMethod("register", FlutterEngine::class.java, FlutterActivity::class.java)
        .invoke(null, flutterEngine, this)
    } catch (_: ClassNotFoundException) {
      // Non-CN flavors intentionally do not package the Pangle bridge.
    } catch (error: Exception) {
      Log.w(tag, "Pangle ad bridge registration failed", error)
    }
  }

  private fun hasRecordAudioPermission(): Boolean {
    return ContextCompat.checkSelfPermission(
      this,
      android.Manifest.permission.RECORD_AUDIO,
    ) == PackageManager.PERMISSION_GRANTED
  }

  private fun startPcmRecording(result: MethodChannel.Result) {
    if (isPcmRecording) {
      result.error("error_busy", "PCM recording is already running.", null)
      return
    }
    if (!hasRecordAudioPermission()) {
      result.error("error_permission", "Microphone permission is not granted.", null)
      return
    }

    val minBufferSize = AudioRecord.getMinBufferSize(
      pcmSampleRate,
      AudioFormat.CHANNEL_IN_MONO,
      AudioFormat.ENCODING_PCM_16BIT,
    )
    if (minBufferSize <= 0) {
      result.error("error_audio_config", "Invalid AudioRecord buffer size.", null)
      return
    }

    try {
      val record = AudioRecord(
        MediaRecorder.AudioSource.VOICE_RECOGNITION,
        pcmSampleRate,
        AudioFormat.CHANNEL_IN_MONO,
        AudioFormat.ENCODING_PCM_16BIT,
        minBufferSize * 2,
      )
      audioRecord = record
      audioBuffer = ByteArrayOutputStream()
      isPcmRecording = true
      record.startRecording()
      audioThread = Thread {
        val chunk = ByteArray(minBufferSize)
        while (isPcmRecording) {
          val read = record.read(chunk, 0, chunk.size)
          if (read > 0) {
            synchronized(this) {
              audioBuffer?.write(chunk, 0, read)
            }
          }
        }
      }.apply {
        name = "AIWT-PcmRecorder"
        start()
      }
      Log.d(tag, "startPcmRecording buffer=$minBufferSize")
      result.success(true)
    } catch (error: Exception) {
      isPcmRecording = false
      audioRecord?.release()
      audioRecord = null
      audioBuffer = null
      result.error(
        "error_record_start",
        "Failed to start PCM recording: ${error.localizedMessage}",
        null,
      )
    }
  }

  private fun stopPcmRecording(): ByteArray {
    if (!isPcmRecording && audioRecord == null) return ByteArray(0)
    isPcmRecording = false
    try {
      audioRecord?.stop()
    } catch (_: Exception) {
    }
    try {
      audioThread?.join(1000)
    } catch (_: InterruptedException) {
      Thread.currentThread().interrupt()
    }
    try {
      audioRecord?.release()
    } catch (_: Exception) {
    }
    audioRecord = null
    audioThread = null
    val bytes = synchronized(this) {
      val data = audioBuffer?.toByteArray() ?: ByteArray(0)
      audioBuffer = null
      data
    }
    Log.d(tag, "stopPcmRecording bytes=${bytes.size}")
    return bytes
  }

  private fun isSpeechRecognitionAvailable(): Boolean {
    return SpeechRecognizer.isRecognitionAvailable(this)
  }

  private fun startSpeechRecognition(
    call: MethodCall,
    result: MethodChannel.Result,
  ) {
    if (recognitionResult != null) {
      result.error("error_busy", "Speech recognition already in progress.", null)
      return
    }

    if (!isSpeechRecognitionAvailable()) {
      result.error(
        "error_unavailable",
        "No speech recognition service is available on this device.",
        null,
      )
      return
    }

    val locale = normalizeLocale(call.argument<String>("locale"))
    Log.d(tag, "startSpeechRecognition locale=$locale")
    val recognizeIntent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
      putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
      putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
      putExtra(RecognizerIntent.EXTRA_PROMPT, "")
      putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
      putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
      putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1200L)
      putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 900L)
      if (!locale.isNullOrBlank()) {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, locale)
      }
    }

    recognitionResult = result
    try {
      val recognizer = SpeechRecognizer.createSpeechRecognizer(this)
      speechRecognizer = recognizer
      recognizer.setRecognitionListener(object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
          Log.d(tag, "onReadyForSpeech")
        }

        override fun onBeginningOfSpeech() {
          Log.d(tag, "onBeginningOfSpeech")
        }

        override fun onRmsChanged(rmsdB: Float) = Unit

        override fun onBufferReceived(buffer: ByteArray?) = Unit

        override fun onEndOfSpeech() {
          Log.d(tag, "onEndOfSpeech")
        }

        override fun onError(error: Int) {
          Log.d(tag, "onError code=$error")
          if (error == SpeechRecognizer.ERROR_NO_MATCH ||
            error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
          ) {
            finishSpeechRecognition("")
          } else {
            finishSpeechRecognitionWithError(
              "error_$error",
              "Speech recognition failed with error code $error.",
            )
          }
        }

        override fun onResults(results: Bundle?) {
          val text = results
            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()
            .orEmpty()
          Log.d(tag, "onResults textLength=${text.length}")
          finishSpeechRecognition(text)
        }

        override fun onPartialResults(partialResults: Bundle?) = Unit

        override fun onEvent(eventType: Int, params: Bundle?) = Unit
      })
      mainHandler.postDelayed(timeoutRunnable, speechTimeoutMs)
      recognizer.startListening(recognizeIntent)
    } catch (error: Exception) {
      finishSpeechRecognitionWithError(
        "error_client",
        "Failed to start speech recognition: ${error.localizedMessage}",
      )
    }
  }

  private fun stopSpeechRecognition() {
    Log.d(tag, "stopSpeechRecognition")
    val recognizer = speechRecognizer
    if (recognizer == null || recognitionResult == null) return
    mainHandler.removeCallbacks(timeoutRunnable)
    mainHandler.postDelayed(timeoutRunnable, 3500L)
    try {
      recognizer.stopListening()
    } catch (error: Exception) {
      finishSpeechRecognitionWithError(
        "error_stop",
        "Failed to stop speech recognition: ${error.localizedMessage}",
      )
    }
  }

  private fun normalizeLocale(locale: String?): String {
    val value = locale?.trim().orEmpty()
    if (value.isEmpty()) return Locale.getDefault().toLanguageTag()
    return value.replace('_', '-')
  }

  private fun finishSpeechRecognition(text: String) {
    val pendingResult = recognitionResult ?: return
    Log.d(tag, "finish success textLength=${text.length}")
    recognitionResult = null
    mainHandler.removeCallbacks(timeoutRunnable)
    speechRecognizer?.destroy()
    speechRecognizer = null
    pendingResult.success(text)
  }

  private fun finishSpeechRecognitionWithError(code: String, message: String) {
    val pendingResult = recognitionResult ?: return
    Log.d(tag, "finish error code=$code message=$message")
    recognitionResult = null
    mainHandler.removeCallbacks(timeoutRunnable)
    speechRecognizer?.destroy()
    speechRecognizer = null
    pendingResult.error(code, message, null)
  }

  override fun onDestroy() {
    stopPcmRecording()
    mainHandler.removeCallbacks(timeoutRunnable)
    speechRecognizer?.destroy()
    speechRecognizer = null
    if (recognitionResult != null) {
      recognitionResult?.success("")
      recognitionResult = null
    }
    super.onDestroy()
  }
}
