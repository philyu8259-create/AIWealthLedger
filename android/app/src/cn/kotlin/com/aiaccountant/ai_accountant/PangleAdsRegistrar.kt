package com.aiaccountant.ai_accountant

import android.app.Activity
import android.content.Context
import android.content.pm.ApplicationInfo
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import com.bytedance.sdk.openadsdk.AdSlot
import com.bytedance.sdk.openadsdk.TTAdConfig
import com.bytedance.sdk.openadsdk.TTAdConstant
import com.bytedance.sdk.openadsdk.TTAdNative
import com.bytedance.sdk.openadsdk.TTAdSdk
import com.bytedance.sdk.openadsdk.TTNativeExpressAd
import com.bytedance.sdk.openadsdk.mediation.ad.MediationAdSlot
import com.bytedance.sdk.openadsdk.mediation.init.MediationConfig
import com.bytedance.sdk.openadsdk.mediation.init.MediationPrivacyConfig
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

object PangleAdsRegistrar {
  private const val tag = "AIWTPangleAds"
  private const val channelName = "com.aiaccounting/pangle_ads"
  private const val bannerViewType = "com.aiaccounting/pangle_banner"

  @Volatile private var started = false
  @Volatile private var initializing = false
  private var initializedAppId: String? = null
  private var lastPersonalizedAdsEnabled: Boolean? = null

  @JvmStatic
  fun register(flutterEngine: FlutterEngine, activity: FlutterActivity) {
    flutterEngine
      .platformViewsController
      .registry
      .registerViewFactory(bannerViewType, PangleBannerViewFactory(activity))

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "initialize" -> initialize(activity, call, result)
          else -> result.notImplemented()
        }
      }
  }

  private fun initialize(
    activity: Activity,
    call: MethodCall,
    result: MethodChannel.Result,
  ) {
    val appId = call.argument<String>("appId")?.trim().orEmpty()
    val appName = call.argument<String>("appName")?.trim().orEmpty()
    val personalizedAdsEnabled =
      call.argument<Boolean>("personalizedAdsEnabled") ?: true
    if (appId.isEmpty()) {
      result.success(false)
      return
    }

    if (started && initializedAppId == appId) {
      updatePersonalizedAds(personalizedAdsEnabled)
      result.success(true)
      return
    }
    if (initializing) {
      result.success(started)
      return
    }

    initializing = true
    activity.runOnUiThread {
      try {
        val debug = isDebuggable(activity)
        val config = TTAdConfig.Builder()
          .appId(appId)
          .appName(appName.ifEmpty { "AI Wealth Tracker" })
          .titleBarTheme(TTAdConstant.TITLE_BAR_THEME_DARK)
          .allowShowNotify(true)
          .supportMultiProcess(false)
          .useMediation(true)
          .debug(debug)
          .setMediationConfig(
            MediationConfig.Builder()
              .setOpenAdnTest(debug)
              .build(),
          )
          .customController(PanglePrivacyController(personalizedAdsEnabled))
          .build()
        TTAdSdk.init(activity.applicationContext, config)
        TTAdSdk.start(object : TTAdSdk.Callback {
          override fun success() {
            initializing = false
            started = true
            initializedAppId = appId
            updatePersonalizedAds(personalizedAdsEnabled)
            Log.i(tag, "Pangle SDK started")
            result.success(true)
          }

          override fun fail(code: Int, msg: String?) {
            initializing = false
            started = false
            Log.w(tag, "Pangle SDK start failed code=$code msg=$msg")
            result.success(false)
          }
        })
      } catch (error: Exception) {
        initializing = false
        started = false
        Log.w(tag, "Pangle SDK initialize failed", error)
        result.success(false)
      }
    }
  }

  private fun updatePersonalizedAds(enabled: Boolean) {
    if (lastPersonalizedAdsEnabled == enabled) return
    lastPersonalizedAdsEnabled = enabled
    try {
      val value = if (enabled) "1" else "0"
      TTAdSdk.updateConfigAuth(
        TTAdConfig.Builder()
          .appId(initializedAppId.orEmpty())
          .customController(PanglePrivacyController(enabled))
          .data("""[{"name":"personal_ads_type","value":"$value"}]""")
          .build(),
      )
    } catch (error: Throwable) {
      Log.w(tag, "Pangle personalized ad update failed", error)
    }
  }

  internal fun isReady(): Boolean = started && TTAdSdk.isSdkReady()

  private fun isDebuggable(context: Context): Boolean {
    return (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
  }
}

private class PanglePrivacyController(
  private val personalizedAdsEnabled: Boolean,
) : com.bytedance.sdk.openadsdk.TTCustomController() {
  override fun isCanUseLocation(): Boolean = false

  override fun alist(): Boolean = false

  override fun isCanUsePhoneState(): Boolean = false

  override fun isCanUseWifiState(): Boolean = true

  override fun isCanUseWriteExternal(): Boolean = false

  override fun isCanUseAndroidId(): Boolean = true

  override fun isCanUsePermissionRecordAudio(): Boolean = false

  override fun isCanUseMessage(): Boolean = false

  override fun userPrivacyConfig(): Map<String, Any> {
    return mapOf("personal_ads_type" to if (personalizedAdsEnabled) "1" else "0")
  }

  override fun getMediationPrivacyConfig(): MediationPrivacyConfig {
    return object : MediationPrivacyConfig() {
      override fun isLimitPersonalAds(): Boolean = !personalizedAdsEnabled

      override fun isProgrammaticRecommend(): Boolean = personalizedAdsEnabled
    }
  }
}

private class PangleBannerViewFactory(
  private val activity: Activity,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
  override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
    @Suppress("UNCHECKED_CAST")
    val params = args as? Map<String, Any?>
    return PangleBannerPlatformView(activity, params.orEmpty())
  }
}

private class PangleBannerPlatformView(
  private val activity: Activity,
  params: Map<String, Any?>,
) : PlatformView {
  private val container = FrameLayout(activity)
  private val codeId = params["codeId"] as? String ?: ""
  private val widthDp = (params["widthDp"] as? Number)?.toFloat() ?: 300f
  private val heightDp = (params["heightDp"] as? Number)?.toFloat() ?: 150f
  private var ad: TTNativeExpressAd? = null
  private var disposed = false
  private var loadAttempts = 0

  init {
    scheduleLoad(initialLoadDelayMs)
  }

  override fun getView(): View = container

  override fun dispose() {
    disposed = true
    ad?.destroy()
    ad = null
    container.removeAllViews()
  }

  private fun scheduleLoad(delayMs: Long) {
    if (disposed) return
    container.postDelayed(
      {
        if (!disposed) load()
      },
      delayMs,
    )
  }

  private fun load() {
    if (disposed) return
    if (codeId.isEmpty()) {
      container.visibility = View.GONE
      return
    }
    if (!PangleAdsRegistrar.isReady()) {
      if (loadAttempts < maxLoadAttempts) {
        loadAttempts += 1
        scheduleLoad(retryLoadDelayMs)
      } else {
        container.visibility = View.GONE
      }
      return
    }

    activity.runOnUiThread {
      if (disposed) return@runOnUiThread
      try {
        loadAttempts += 1
        val adNative = TTAdSdk.getAdManager().createAdNative(activity)
        val adSlot = AdSlot.Builder()
          .setCodeId(codeId)
          .setExpressViewAcceptedSize(widthDp, heightDp)
          .setMediationAdSlot(
            MediationAdSlot.Builder()
              .setExtraObject("show_adn_load_error_detail", true)
              .build(),
          )
          .setAdCount(1)
          .build()

        adNative.loadBannerExpressAd(
          adSlot,
          object : TTAdNative.NativeExpressAdListener {
            override fun onError(code: Int, message: String?) {
              Log.w("AIWTPangleAds", "Banner load failed code=$code msg=$message")
              if (!disposed && loadAttempts < maxLoadAttempts) {
                scheduleLoad(retryLoadDelayMs)
              } else {
                container.visibility = View.GONE
              }
            }

            override fun onNativeExpressAdLoad(ads: MutableList<TTNativeExpressAd>?) {
              val loadedAd = ads?.firstOrNull()
              if (loadedAd == null) {
                if (!disposed && loadAttempts < maxLoadAttempts) {
                  scheduleLoad(retryLoadDelayMs)
                  return
                }
                container.visibility = View.GONE
                return
              }
              ad = loadedAd
              loadedAd.setExpressInteractionListener(
                object : TTNativeExpressAd.ExpressAdInteractionListener {
                  override fun onAdShow(view: View?, type: Int) = Unit
                  override fun onAdClicked(view: View?, type: Int) = Unit

                  override fun onRenderFail(view: View?, msg: String?, code: Int) {
                    Log.w("AIWTPangleAds", "Banner render failed code=$code msg=$msg")
                    container.visibility = View.GONE
                  }

                  override fun onRenderSuccess(view: View?, width: Float, height: Float) {
                    Log.i("AIWTPangleAds", "Banner render success ${width}x$height")
                  }
                },
              )
              val adView = loadedAd.expressAdView
              if (adView == null) {
                container.visibility = View.GONE
                return
              }
              container.removeAllViews()
              container.visibility = View.VISIBLE
              container.addView(
                adView,
                FrameLayout.LayoutParams(
                  FrameLayout.LayoutParams.MATCH_PARENT,
                  FrameLayout.LayoutParams.MATCH_PARENT,
                ),
              )
            }
          },
        )
      } catch (error: Exception) {
        Log.w("AIWTPangleAds", "Banner request failed", error)
        container.visibility = View.GONE
      }
    }
  }

  private companion object {
    const val initialLoadDelayMs = 3000L
    const val retryLoadDelayMs = 2500L
    const val maxLoadAttempts = 3
  }
}
