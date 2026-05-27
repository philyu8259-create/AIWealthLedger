FLUTTER ?= flutter
SELECT_APP_VARIANT ?= ./tools/select_app_variant.sh
AUDIT_CN_NO_GOOGLE ?= ./tools/android_audit_cn_no_google.sh
APK_PATH ?=

QWEN_API_KEY ?=
BAIDU_AK ?=
BAIDU_SK ?=
OCR_SPACE_API_KEY ?=
ZHITU_API_TOKEN ?=
ALIYUN_FC_API ?=
ALIYUN_ACCESS_KEY_ID ?=
ALIYUN_ACCESS_KEY_SECRET ?=
ALIYUN_ASR_APP_KEY ?=
GOOGLE_IOS_CLIENT_ID ?=
GOOGLE_SERVER_CLIENT_ID ?=
GOOGLE_IOS_REVERSED_CLIENT_ID ?=
GOOGLE_ANDROID_CLIENT_ID ?=
GEMINI_API_KEY ?=
FINNHUB_API_KEY ?=

CN_DART_DEFINE_ARGS := \
	--dart-define=APP_FLAVOR=cn \
	--dart-define=QWEN_API_KEY=$(QWEN_API_KEY) \
	--dart-define=BAIDU_AK=$(BAIDU_AK) \
	--dart-define=BAIDU_SK=$(BAIDU_SK) \
	--dart-define=OCR_SPACE_API_KEY=$(OCR_SPACE_API_KEY) \
	--dart-define=ZHITU_API_TOKEN=$(ZHITU_API_TOKEN) \
	--dart-define=ALIYUN_FC_API=$(ALIYUN_FC_API) \
	--dart-define=ALIYUN_ACCESS_KEY_ID=$(ALIYUN_ACCESS_KEY_ID) \
	--dart-define=ALIYUN_ACCESS_KEY_SECRET=$(ALIYUN_ACCESS_KEY_SECRET) \
	--dart-define=ALIYUN_ASR_APP_KEY=$(ALIYUN_ASR_APP_KEY)

.PHONY: bootstrap analyze test ci ios-build-check android-static-check \
	android-build-cn android-build-intl android-build-cn-aab android-build-intl-aab \
	test-explicit-cn test-explicit-intl android-audit-cn-no-google

bootstrap:
	$(FLUTTER) pub get

analyze:
	$(FLUTTER) analyze

android-static-check:
	@echo ">>> android-static-check: manifest permissions + package visibility"
	@rg -n --no-heading 'uses-permission android:name="android.permission.INTERNET"' android/app/src/main/AndroidManifest.xml >/dev/null || \
		(echo "FAIL: missing INTERNET permission in android/app/src/main/AndroidManifest.xml"; exit 1)
	@rg -n --no-heading 'uses-permission android:name="android.permission.RECORD_AUDIO"' android/app/src/main/AndroidManifest.xml >/dev/null || \
		(echo "FAIL: missing RECORD_AUDIO permission in android/app/src/main/AndroidManifest.xml"; exit 1)
	@rg -n --no-heading 'uses-permission android:name="android.permission.CAMERA"' android/app/src/main/AndroidManifest.xml >/dev/null || \
		(echo "FAIL: missing CAMERA permission in android/app/src/main/AndroidManifest.xml"; exit 1)
	@rg -n --no-heading 'android.speech.RecognitionService' android/app/src/main/AndroidManifest.xml >/dev/null || \
		(echo "FAIL: missing speech visibility query action android.speech.RecognitionService in android/app/src/main/AndroidManifest.xml"; exit 1)
	@echo "PASS: required permissions + speech query exist"
	@rg -n --no-heading 'android:allowBackup="true"' android/app/src/main/AndroidManifest.xml >/dev/null || \
		(echo "FAIL: allowBackup is not explicitly set to true in android/app/src/main/AndroidManifest.xml"; exit 1)
	@rg -n --no-heading 'android:fullBackupContent="@xml/secure_storage_backup_rules"' android/app/src/main/AndroidManifest.xml >/dev/null || \
		(echo "FAIL: missing android:fullBackupContent in android/app/src/main/AndroidManifest.xml"; exit 1)
	@test -f android/app/src/main/res/xml/secure_storage_backup_rules.xml || \
		(echo "FAIL: missing android/app/src/main/res/xml/secure_storage_backup_rules.xml"; exit 1)
	@rg -n --no-heading 'exclude domain="sharedpref"' android/app/src/main/res/xml/secure_storage_backup_rules.xml >/dev/null || \
		(echo "FAIL: backup rules missing sharedpref exclusion for flutter_secure_storage"; exit 1)
	@echo "PASS: backup config for flutter_secure_storage found"
	@rg -n --no-heading 'Flavorless Android tasks are blocked' android/app/build.gradle.kts >/dev/null || \
		(echo "FAIL: flavorless release guard message missing in android/app/build.gradle.kts"; exit 1)
	@rg -n --no-heading 'flutter build appbundle --release --flavor cn --dart-define=APP_FLAVOR=cn' android/app/build.gradle.kts >/dev/null || \
		(echo "FAIL: cn flavor release guidance missing in android/app/build.gradle.kts"; exit 1)
	@rg -n --no-heading 'flutter build appbundle --release --flavor intl --dart-define=APP_FLAVOR=intl' android/app/build.gradle.kts >/dev/null || \
		(echo "FAIL: intl flavor release guidance missing in android/app/build.gradle.kts"; exit 1)
	@echo "PASS: release flavor guard text present"

test:
	$(FLUTTER) test

ci: bootstrap analyze test android-static-check test-explicit-cn test-explicit-intl

ios-build-check:
	./build_check.sh

android-build-cn:
	$(SELECT_APP_VARIANT) cn
	$(FLUTTER) build apk --release --flavor cn $(CN_DART_DEFINE_ARGS)

android-build-intl:
	$(SELECT_APP_VARIANT) intl
	$(FLUTTER) build apk --release --flavor intl --dart-define=APP_FLAVOR=intl

android-build-cn-aab:
	$(SELECT_APP_VARIANT) cn
	$(FLUTTER) build appbundle --release --flavor cn $(CN_DART_DEFINE_ARGS)

android-build-intl-aab:
	$(SELECT_APP_VARIANT) intl
	$(FLUTTER) build appbundle --release --flavor intl --dart-define=APP_FLAVOR=intl

test-explicit-cn:
	$(SELECT_APP_VARIANT) cn
	$(FLUTTER) test test/app_profile_service_explicit_flavor_test.dart --dart-define=APP_FLAVOR=cn

test-explicit-intl:
	$(SELECT_APP_VARIANT) intl
	$(FLUTTER) test test/app_profile_service_explicit_flavor_test.dart --dart-define=APP_FLAVOR=intl

android-audit-cn-no-google:
	$(AUDIT_CN_NO_GOOGLE) $(APK_PATH)
