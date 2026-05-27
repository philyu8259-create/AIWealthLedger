# Huawei AppGallery Review Log

## 2026-05-16 Baseline

Workspace:

- Path: `/Users/phil/Desktop/Codex Project/AI Wealth Tracker-android`
- Branch: `codex/android-mvp`
- Worktree: linked git worktree under the main `AI Wealth Tracker` repository.
- Status: existing working tree already contained many modified and untracked project files before this release-prep pass. Huawei release changes should stay narrowly scoped.

Checks:

- `make android-static-check` passed.
  - Required Android permissions and speech query entries are present.
  - Flutter secure storage backup exclusion is present.
  - Flavorless Android build guard text is present.
- `flutter test test/app_profile_service_explicit_flavor_test.dart --dart-define=APP_FLAVOR=cn` passed.
  - 2 tests passed.
  - 1 INTL-only case skipped because the build flavor was CN.

Current blockers:

- `android/app/build.gradle.kts` release builds still use the debug signing config. This must be replaced with a production signing configuration before Huawei review submission.
- Pangle/穿山甲 integration is now in scope and must be completed before final privacy-policy review and release package verification.
- External confirmation is still needed for Huawei developer verification, Pangle account/entity eligibility, APP备案, ICP备案/public policy URL hosting, and software copyright or authorization materials.

## 2026-05-16 Release Signing Update

Changes:

- `android/app/build.gradle.kts` now points release builds at a dedicated `release` signing config instead of the debug config.
- Signing values can be provided through ignored local file `android/key.properties` or CI/environment variables:
  - `AI_ACCOUNTANT_ANDROID_KEYSTORE_FILE`
  - `AI_ACCOUNTANT_ANDROID_STORE_PASSWORD`
  - `AI_ACCOUNTANT_ANDROID_KEY_ALIAS`
  - `AI_ACCOUNTANT_ANDROID_KEY_PASSWORD`
- `.gitignore` now explicitly ignores Android signing material under `android/key.properties`, `android/**/*.jks`, and `android/**/*.keystore`.
- `docs/android_release_checklist.md` and `.env.example` now document the required signing inputs.

Verification:

- `make android-static-check` passed after the signing change.
- Static search confirms release no longer uses `signingConfigs.getByName("debug")` and does use `signingConfigs.getByName("release")`.
- Gradle dry-run verification is blocked on this machine because Java/JDK is not installed or not discoverable:
  - `./gradlew :app:bundleCnRelease --dry-run`
  - Failure: `Unable to locate a Java Runtime.`
  - `flutter doctor -v` reports Android toolchain warning: `Could not determine java version`.

Remaining signing blocker:

- Resolved on 2026-05-16: installed/configured OpenJDK 17.0.19 with Flutter `jdk-dir`.
- `./gradlew :app:bundleCnRelease --dry-run` now reaches Gradle configuration and fails with the intended clear signing-config error when release signing values are missing.

## 2026-05-16 App Name Update

Decision:

- Chinese app name changed from `AI财富记账本` / older `AI财富账本` wording to `财富记账本`.

Updated surfaces:

- Android resource labels under `android/app/src/main/res/values*` and `android/app/src/cn/res/values*`.
- In-app Chinese strings in `lib/l10n/app_strings.dart`.
- Huawei submission draft, Android release checklist, support page, privacy policy, EULA, App Store/listing draft, README, and `.env.example` comments.

Verification:

- Static search found no remaining `AI财富记账本`, `AI财富账本`, `AI 财富记账本`, `升级 财富记账本`, or `关于 财富记账本` in the checked release/code surfaces.
- `make android-static-check` passed.
- `flutter test test/app_profile_service_explicit_flavor_test.dart --dart-define=APP_FLAVOR=cn` passed.

## 2026-05-16 First-Launch Privacy Gate

Finding:

- `WelcomePage` previously wrote `onboarding_viewed` through `FunnelAnalyticsService` during `initState`, before the user explicitly accepted the privacy policy.
- Login entry points showed agreement copy but did not block guest, phone, Google, or Apple entry until explicit consent.

Changes:

- `AIPrivacyConsentService` now stores an app-level first-launch privacy consent value in addition to OCR, voice, and text AI consent.
- `WelcomePage` now shows a blocking privacy dialog before tracking onboarding or continuing guest/phone/international sign-in.
- Declining the dialog leaves the user on the welcome screen and does not proceed into login.
- `AppProfileService`, Android labels, and app listing materials now use the Chinese app name `财富记账本`.

Verification:

- Added `test/app_privacy_consent_service_test.dart`.
- `flutter test test/app_privacy_consent_service_test.dart test/app_profile_service_explicit_flavor_test.dart --dart-define=APP_FLAVOR=cn` passed.
- `make android-static-check` passed.
- Static search found no remaining old Chinese app names in checked release/code surfaces.

## 2026-05-16 Personalized Ads Preference

Changes:

- Added `AdPreferencesService` with persisted `personalized_ads_enabled_v1`.
- Added a CN-only settings switch: `设置 → 个性化广告推荐`.
- Updated Huawei submission draft to state the close path for personalized ads.

Verification:

- Added `test/ad_preferences_service_test.dart`.
- `flutter test test/ad_preferences_service_test.dart test/app_privacy_consent_service_test.dart test/app_profile_service_explicit_flavor_test.dart --dart-define=APP_FLAVOR=cn` passed.
- `flutter analyze` passed.
- `make android-static-check` passed.

Remaining Pangle blocker:

- Actual Pangle SDK integration still needs Pangle account/entity approval, App ID, ad slot IDs, and a final ad placement decision.

## 2026-05-16 Pangle Console Snapshot

Observed in Chrome:

- Pangle/GroMore app: `财富记账本`
- App/media ID: `5827353`
- App status: `测试`
- Created at: `2026-05-16 19:08:28`
- Existing ad slot: `开屏`
- Existing open-screen ad slot ID: `104073928`
- Created first-release ad slot: `首页底部Banner`
- First-release Banner ad slot ID: `104073039`

Console next steps shown:

- Bind ad network account.
- Create or manage ad slots.
- Integrate GroMore SDK.
- Optionally enable automatic management.

Implementation note:

- Product decision: first Huawei release should avoid the existing open-screen ad slot and use a lighter Banner / native-feed placement instead.
- A splash/open-screen ad has stricter UX and compliance risk than a home/report native or banner placement.
- Console setting used for `首页底部Banner`: Banner type, smart manager disabled, default `300*150 dp/pt` code size.

## 2026-05-16 AppGallery Connect Snapshot

Observed in Chrome:

- Account: `hid41477735`
- Entity: `青岛序帆智联信息科技有限公司`
- Account status: authenticated / `已认证`
- Android app list: empty / `暂无数据`
- In-production apps: 0
- In-review apps: 0
- AppGallery Connect blocks Development & Services behind an AGC agreement package that requires developer acceptance.

Implementation note:

- Create the Android app record first with package name `com.aiaccountant.ai_accountant.cn`.
- Then configure Huawei IAP subscription products `ai_wealth_tracker_monthly` and `ai_wealth_tracker_yearly`.
- Free users may see ads after privacy consent; active members should not request or display ads.

## 2026-05-16 Pangle Client Integration

Changes:

- Added Dart-side `PangleAdService` with home Banner config:
  - App/media ID: `5827353`
  - Home Banner code ID: `104073039`
  - Size: `300*150 dp`
- Added `HomePangleBannerAd` to the bottom of the home page, after the recent entries section.
- Banner is gated to CN Android only, after app privacy consent, and only for non-member users.
- Active VIP/member users do not initialize, request, or display Pangle ads.
- Added CN-only Android bridge using the official Pangle Android SDK through a Flutter PlatformView:
  - `android/app/src/cn/kotlin/com/aiaccountant/ai_accountant/PangleAdsRegistrar.kt`
  - `android/app/src/cn/AndroidManifest.xml`
  - `android/app/src/cn/res/xml/pangle_file_paths.xml`
- Added Pangle Maven repository and CN-only `cnImplementation` SDK dependency, keeping INTL builds from packaging the CN ad SDK.

Verification:

- Added `test/pangle_ad_service_test.dart`.
- `flutter test test/pangle_ad_service_test.dart` passed.
- `flutter test test/ad_preferences_service_test.dart test/vip_service_platform_test.dart test/pangle_ad_service_test.dart` passed.
- `flutter analyze` passed with no issues.
- Pangle Maven artifact probe passed without Gradle/JDK:
  - `ads-sdk-pro-7.6.1.2.pom` returned HTTP 200.
  - `ads-sdk-pro-7.6.1.2.aar` returned HTTP 200, size about 11.4 MB.
- Android native compilation, Gradle dependency resolution, and real-device ad loading are still blocked because this machine has no usable JDK:
  - `/usr/libexec/java_home -V`: `Unable to locate a Java Runtime.`
  - `java -version`: `Unable to locate a Java Runtime.`
  - `flutter doctor -v`: Android toolchain warning, `Could not determine java version`.

Follow-up verification after JDK setup:

- Installed/configured OpenJDK 17.0.19 through Homebrew.
- `flutter doctor -v` reports no issues and uses `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home/bin/java`.
- `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :app:assembleCnDebug --stacktrace` passed.
- Fixed Huawei IAP manifest merge conflict by explicitly replacing `android:allowBackup` in the app manifest.
- Adjusted the Pangle native bridge to the GroMore `mediation-sdk:7.6.1.1` API surface and the platform-generated Banner sample for ad slot `104073039`.
- Installed `build/app/outputs/apk/cn/debug/app-cn-debug.apk` on connected Android device `ZY22LDKR8L` successfully.
- After the device was unlocked, cold-launched the CN debug APK successfully; the app stays in foreground and no longer crashes on Pangle provider startup.
- GroMore SDK startup succeeds with `MSDK init finish.........hasConfig:true` and `AIWTPangleAds: Pangle SDK started`.
- Home Banner request reaches the GroMore ad slot `104073039` and the configured underlying Pangle code slot `981713677`.
- Client-side request code was compared against the Pangle console "快速集成" generated Banner sample:
  - dependency: `com.pangle.cn:mediation-sdk:7.6.1.1`
  - request method: `loadBannerExpressAd`
  - ad slot: `.setCodeId("104073039").setImageAcceptedSize(300,150)`
  - display: `getExpressAdView()` without manually calling `render()`
- Local debug-device privacy consent was set only to trigger ad verification; production still gates ad initialization behind real user privacy consent and active VIP users do not request ads.

Final ad-loading verification:

- The `40029` failure was traced to request timing, not an invalid GroMore/Pangle code slot. A Banner request fired about 150 ms after `TTAdSdk.start` could run before the internal Pangle ADN initialization finished.
- Added a production-safe Banner load delay/retry guard:
  - first Banner request waits 3 seconds after PlatformView creation;
  - failures or not-ready state retry up to 3 total attempts;
  - persistent failure hides the ad container.
- For template Banner requests, the native bridge now sends `setExpressViewAcceptedSize(widthDp, heightDp)` and keeps the GroMore ADN diagnostic switch enabled for debug evidence.
- Final real-device run on `ZY22LDKR8L`:
  - `isOpenAdnTest:true` in debug only;
  - `104073039 -> pangle / 981713677`;
  - `TTMediationSDK_104073039_fill_AdNetWorkName[pangle] ... 请求成功`;
  - `广告加载成功！给外部回调`;
  - `TTBannerView onRenderSuccess 渲染成功`.
- Remaining external check before submission: confirm Pangle account contract/settlement status and ad slot approval/formal status.

## 2026-05-17 Huawei IAP Product Query Verification

Investigation:

- AppGallery Connect app and product configuration were confirmed correct for package `com.aiaccountant.ai_accountant.cn`, App ID `117736975`, and non-consumable product `ai_wealth_tracker_lifetime_ad_free`.
- The local debug APK was reinstalled with AppGallery as the installer:
  - `adb install -i com.huawei.appmarket -r build/app/outputs/apk/cn/debug/app-cn-debug.apk`
  - Device verification: `installerPackageName=com.huawei.appmarket`.
- The earlier failure was not caused by missing product metadata. First product-query attempts triggered HMS Core update UI `暂时无法更新，请稍后再试。（102）`.
- Focused logcat showed an HMS Core dynamic-framework crash before recovery:
  - process `com.huawei.hwid.core`
  - `NoClassDefFoundError: Failed resolution of: Lcom/huawei/gson/Gson;`
  - missing class path under `/data/user_de/0/com.huawei.hwid/files/framework/earlyinstall/com.huawei.hms.fwkit/...`
- After HMS Core finished loading dynamic kits, a cold-launch retest succeeded.

Verification:

- Rebuilt CN debug APK after the UI fallback patch:
  - `flutter analyze` passed.
  - `flutter test test/vip_service_platform_test.dart test/pangle_ad_service_test.dart` passed.
  - `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :app:assembleCnDebug --stacktrace` passed.
- Installed the rebuilt CN debug APK with AppGallery installer attribution.
- Real-device retest on `ZY22LDKR8L`:
  - `HMSSDK_ProductInfoTaskApiCall: dealSuccess`
  - `obtainProductInfo result=0`
  - `[VipSheet] queryProductDetails found=1, notFound=`
  - `[VipSheet] product id=ai_wealth_tracker_lifetime_ad_free, price=¥28.00, currencyCode=CNY, rawPrice=28.0`
- Screenshot captured locally:
  - `/tmp/wealth-iap-final-price.png`

Code hardening:

- `settings_page.dart` now tracks product-loading failure separately from purchase loading.
- If Huawei IAP product loading fails, the paywall shows a clear HMS Core retry message and a retry button instead of leaving the primary CTA stuck on `价格加载中...`.
- No payment was started during this verification pass; purchase flow still requires explicit confirmation before tapping `立即开通`.

## 2026-05-17 Huawei IAP Purchase Blocker

Investigation:

- After explicit user confirmation, the lifetime product purchase button was tapped in sandbox.
- The app successfully entered the Huawei IAP create-order path, but HMS returned:
  - `responseMessage = IAP_APP_NOT_EXISTED`
  - `subErrCode = 101`
  - `exitService = 60002`
  - Flutter-side purchase status: `PurchaseStatus.error`
- Adding the Huawei CP ID manifest metadata made the merged manifest explicitly include both:
  - `com.huawei.hms.client.appid = appid=117736975`
  - `com.huawei.hms.client.cpid = cpid=10086000942590989`
- The same purchase error still occurred after rebuilding and reinstalling with AppGallery installer attribution, so the blocker is not a missing client-side CP ID alone.

Root cause:

- AppGallery Connect `项目设置 -> API管理` showed `应用内支付服务` turned off.
- Attempting to enable it required accepting the `华为应用市场联运服务协议`; after user confirmation this agreement was accepted.
- Enabling IAP then produced another prerequisite prompt: the account must first open merchant service and sign the `华为商户服务协议`.
- Developer console `管理中心 -> 商户服务` currently shows:
  - service status: `未开通`
  - domestic receiving account: `审核中`
  - review estimate: about `1-2 个工作日`
- Therefore the current `IAP_APP_NOT_EXISTED / 60002` purchase failure is a Huawei backend merchant-service activation blocker, not a Dart/Flutter product-query bug.

Next action:

- Wait for Huawei merchant service / domestic receiving account review to finish.
- After service status becomes active, return to `项目设置 -> API管理` and enable `应用内支付服务`.
- Retest purchase, restore purchase, and ad removal after successful lifetime purchase.

## 2026-05-16 Huawei IAP And CN Package Audit

Huawei IAP client hardening:

- CN Android resolves VIP products to Huawei IAP, using:
  - monthly: `ai_wealth_tracker_monthly`
  - yearly: `ai_wealth_tracker_yearly`
- `HuaweiIapVipGateway` now maps Huawei subscription purchase data as full `InAppPurchaseData` JSON, preserving `purchaseToken`, `expirationDate`, order fields, and related subscription fields.
- Huawei `inAppDataSignature` is preserved as receipt signature and sent to the cloud sync payload with:
  - `store_provider=huawei`
  - `receipt_source=huawei_iap`
  - `receipt_signature`
  - `product_id`
- When Huawei returns `expirationDate`, local VIP expiry uses that platform timestamp directly instead of adding another month/year on the client.
- `VipService.removesAds` remains tied to `isVip`, so an active Huawei subscription prevents Pangle initialization and Banner display.

Verification:

- `flutter test test/vip_service_platform_test.dart test/pangle_ad_service_test.dart` passed.
- `flutter analyze` passed.
- `make android-static-check` passed after the lifetime ad-free switch.
- `make android-audit-cn-no-google APK_PATH=build/app/outputs/apk/cn/debug/app-cn-debug.apk` passed after the lifetime ad-free switch.

AppGallery Connect product draft:

- Draft product type is `非消耗型`, matching a permanent ad-removal entitlement.
- Draft product ID is `ai_wealth_tracker_lifetime_ad_free`.
- Draft Simplified Chinese name is `财富记账本终身去广告`.
- Draft description is `一次购买，永久去除应用内广告。`
- Product information was saved after explicit confirmation.
- Sales range was changed from global to China only, shown as `已选择1个国家/地区`.
- Price was configured in AppGallery Connect as `中国(CN) CNY 28.00`.
- Product was activated after confirming the AppGallery Connect prompt `此商品将被开放购买`; the product list now shows status `有效`.
- Sandbox tester setup was opened at `用户与访问 -> 沙盒测试 -> 测试账号`; AppGallery Connect requires a real Huawei account by phone number or email plus a display name.
- The sandbox tester was added manually in AppGallery Connect by the account owner.
- The CN debug signing SHA256 fingerprint was added in `项目设置 -> 常规 -> SHA256证书指纹` after the real-device HMS IAP environment check returned `907135702`.
- After adding the debug SHA256 fingerprint, the previous `907135702` gateway error no longer appeared.
- The previous account blocker is resolved on the test phone: HMS Core account center shows sandbox account `19560772181` signed in.
- Current real-device blocker is HMS Core / IAP runtime update failure on the Motorola PRC ROM test device:
  - AppGallery updated HMS Core from `6.15.6.312` to `6.15.6.332`; HMS Core detail page now shows `打开`.
  - Opening HMS Core surfaced account-security and notification authorization prompts; these were dismissed/cleared before retesting.
  - Retesting the paywall still shows the HMS Core dialog `暂时无法更新，请稍后再试。（102）`.
  - `VipSheet` logs `queryProductDetails found=0, notFound=ai_wealth_tracker_lifetime_ad_free` and then `Huawei IAP product query timed out`.
  - Logcat shows `IAP_APK[6.26.2.300]` loads, but the HMS kit update flow reports `all kit has not new version` and `uiErrCode: 102`.
- HMS account/runtime logs also report `Is Not China Rom, not support vudid` even though Android system properties identify the device as Motorola PRC ROM.
- Treat this as an environment/device blocker. Continue Huawei IAP purchase validation on a Huawei/Honor device or AppGallery Connect cloud testing; do not treat the Motorola result as proof that the AppGallery product configuration is wrong.
- `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :app:assembleCnDebug --stacktrace` passed.
- `make android-static-check` passed.
- `make android-audit-cn-no-google APK_PATH=build/app/outputs/apk/cn/debug/app-cn-debug.apk` passed.
- APK identity check:
  - package: `com.aiaccountant.ai_accountant.cn`
  - versionName: `1.4.1`
  - versionCode: `1`
  - minSdk: `24`
  - targetSdk: `36`
- CN Debug APK contains expected Huawei IAP and Pangle/穿山甲 markers, and no direct `google_sign_in`, Play services, Firebase, or `com/google/android/gms` markers.

Remaining external checks:

- Create/confirm the Huawei non-consumable lifetime ad-free product in AppGallery Connect.
- Run Huawei IAP product-query, purchase, restore, and ad-removal tests on a Huawei/Honor device or AppGallery Connect cloud testing because the current Motorola device is blocked by HMS Core `102`.
- Before release signing, add the final release/upload keystore SHA256 fingerprint to the same AppGallery Connect app settings.
- The configured Huawei sandbox tester is signed in on the Motorola device, but product-query still cannot pass because HMS Core returns update failure `102`.
- Confirm backend verifies Huawei receipt/token/signature before treating cloud VIP as authoritative.

## 2026-05-16 AppGallery App Record And AG Connect Config

AppGallery Connect:

- Created project: `财富记账本`
- Created Android app record:
  - App name: `财富记账本`
  - Package name: `com.aiaccountant.ai_accountant.cn`
  - App ID: `117736975`
  - Project ID: `101653523864137209`
  - Created at: `2026-05-16 22:50:26`
- Downloaded the generated AG Connect config and placed it at `android/app/src/cn/agconnect-services.json`.
- Verified the config package name is `com.aiaccountant.ai_accountant.cn` and the config App ID is `117736975`.

Android build config:

- Added Huawei Maven repository to Gradle plugin/dependency resolution.
- Added AG Connect Gradle plugin `com.huawei.agconnect:agcp:1.9.1.304`.
- Kept Android Gradle Plugin pinned to `8.11.1` in `buildscript` so Huawei AGCP's legacy plugin check does not downgrade or break the Kotlin DSL Android extension.
- Applied `com.huawei.agconnect` to the app module.
- `cnDebug`, `cnRelease`, and `cnProfile` use `android/app/src/cn/agconnect-services.json`; `intl*` variants have no Huawei config file.

Huawei subscription blocker and product decision:

- In `运营 -> 产品运营 -> 商品管理`, choosing product type `自动续期订阅` shows a Huawei warning:
  - automatic-renewal subscription service must be requested through the app joint-operation/business contact flow before subscription products can be created.
- Product decision changed after this blocker:
  - CN first release uses a `非消耗型` one-time product instead of automatic-renewal subscriptions.
  - Product ID: `ai_wealth_tracker_lifetime_ad_free`
  - Price: CNY `28`
  - Entitlement: lifetime ad removal.
- Rationale:
  - `消耗型` is for products that are consumed or depleted.
  - Lifetime ad removal is a durable entitlement and should use `非消耗型`.

Verification after AG Connect config:

- `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :app:assembleCnDebug --stacktrace` passed.
- `make android-static-check` passed.
- `make android-audit-cn-no-google APK_PATH=build/app/outputs/apk/cn/debug/app-cn-debug.apk` passed.

## 2026-05-16 CN Lifetime Ad-Free IAP Switch

Decision:

- Replace CN/Huawei monthly/yearly subscription plan with a one-time `非消耗型` lifetime ad-free purchase.
- Product ID: `ai_wealth_tracker_lifetime_ad_free`
- Target price: CNY `28`

Client changes:

- Added `VipType.lifetime`.
- CN/Huawei product query now requests only `ai_wealth_tracker_lifetime_ad_free`.
- `HuaweiIapVipGateway` uses `IapClient.IN_APP_NONCONSUMABLE` for this product.
- Restore flow checks non-consumable purchases and subscription purchases for backward compatibility.
- Lifetime purchases activate `VipType.lifetime` with a far-future entitlement date (`2099-12-31 23:59:59`) so existing `isVip` and `removesAds` gates continue to work.
- Settings paywall shows a single lifetime ad-free product for Huawei/CN; monthly/yearly options remain for non-Huawei stores.

Verification:

- `flutter test test/vip_service_platform_test.dart test/pangle_ad_service_test.dart` passed.
- `flutter analyze` passed.

## 2026-05-17 Huawei IAP Device Runtime Blocker

Code hardening:

- Removed the `isEnvReady` preflight wait before `obtainProductInfo` because on the Motorola PRC ROM device it drives HMS Core into an update flow that fails with `102`.
- Added 20-second timeouts around Huawei IAP product query, purchase, and restore calls so the paywall does not stay in a permanent loading state when HMS Core never returns.
- Added paywall debug logging for `ProductDetailsResponse.error` to preserve the exact HMS/IAP failure code and message.

Fresh verification:

- `dart format lib/services/huawei_iap_vip_gateway.dart lib/features/accounting/presentation/pages/settings_page.dart` passed.
- `flutter analyze` passed.
- `flutter test test/vip_service_platform_test.dart test/pangle_ad_service_test.dart` passed.
- `JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home ./gradlew :app:assembleCnDebug --stacktrace` passed.
- `app-cn-debug.apk` installed successfully on `ZY22LDKR8L`.

Real-device retest after clearing HMS account prompts:

- HMS Core account center shows the sandbox tester phone number `19560772181`.
- AppGallery HMS Core detail page shows version `6.15.6.332` and an `打开` action, not an update action.
- The paywall still receives HMS Core dialog `暂时无法更新，请稍后再试。（102）`.
- Logcat shows `IAP_APK[6.26.2.300]`, `all kit has not new version`, `uiErrCode: 102`, and `Is Not China Rom, not support vudid`.
- Client-side result remains a controlled timeout: `Huawei IAP product query timed out`.
- AppGallery Connect cloud resources checked:
  - `质量 -> 云测试` shows daily gifted time `600` minutes.
  - `质量 -> 云调试` shows remaining discount time `0` minutes, package balance `0` minutes, pay-as-you-go not enabled, and `0` available devices.
  - Cloud debugging is therefore not immediately usable for manual Huawei IAP validation under the current account state.

Decision:

- Keep the client timeout/logging hardening.
- Move purchase-chain validation to Huawei/Honor hardware, or explicitly enable/use AppGallery Connect cloud testing/debugging before attempting any actual sandbox purchase.
