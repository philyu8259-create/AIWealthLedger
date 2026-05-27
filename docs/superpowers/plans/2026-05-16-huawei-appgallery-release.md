# Huawei AppGallery Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare the CN Android flavor of 财富记账本 for Huawei AppGallery review submission.

**Architecture:** Treat the CN flavor as the release target and keep INTL/Google-only behavior isolated. Work from compliance and release blockers first, then package, verify, and prepare AppGallery Connect metadata.

**Tech Stack:** Flutter, Android Gradle, Kotlin Android, AppGallery Connect, GitHub Pages support/privacy documents.

---

## File Structure

- Modify: `android/app/build.gradle.kts` for release signing, version sanity, and CN package release readiness.
- Modify: `android/app/src/main/AndroidManifest.xml` only if permission scope changes after review.
- Modify: `android/app/src/cn/res/values*/strings.xml` if the Huawei listing name needs to match the CN storefront name.
- Modify: `lib/app/app_flavor.dart` if CN privacy or terms URLs need Huawei-specific production URLs.
- Modify: `pubspec.cn.yaml` and Android Gradle files if the Pangle/穿山甲 Flutter plugin or native SDK requires dependency wiring.
- Modify: `android/app/src/cn/AndroidManifest.xml` for Pangle-required provider declarations after confirming the current SDK documentation.
- Create/modify: `lib/services/pangle_ad_service.dart` and relevant UI files for CN-only ad initialization, ad slot loading, and graceful no-ad fallback.
- Modify: `privacy_policy.html`, `support.html`, `eula.html`, `PRIVACY.md`, `EULA.md` for China-market compliance wording, SDK disclosures, permissions, account deletion, and contact details.
- Modify: `docs/android_release_checklist.md` to keep Android release commands and verification results current.
- Create/modify: `docs/huawei_appgallery_submission.md` as the paste-ready AppGallery Connect submission packet.
- Create/modify: `docs/huawei_appgallery_review_log.md` to record checks, generated artifacts, APK/AAB paths, and unresolved external items.

---

### Task 1: Baseline Audit

**Files:**
- Read: `android/app/build.gradle.kts`
- Read: `android/app/src/main/AndroidManifest.xml`
- Read: `docs/android_release_checklist.md`
- Read: `privacy_policy.html`
- Read: `support.html`
- Read: `eula.html`
- Modify: `docs/huawei_appgallery_review_log.md`

- [x] Run `git status --short` and record that the tree already contains existing user/work-in-progress changes.
- [x] Run `make android-static-check`.
- [x] Run `flutter test test/app_profile_service_explicit_flavor_test.dart --dart-define=APP_FLAVOR=cn`.
- [x] Record current blockers and passing checks in `docs/huawei_appgallery_review_log.md`.

### Task 2: Release Signing Readiness

**Files:**
- Modify: `android/app/build.gradle.kts`
- Modify: `.gitignore`
- Modify: `.env.example`
- Modify: `docs/android_release_checklist.md`

- [x] Replace debug signing for `release` with a production signing config loaded from local Gradle properties or environment variables.
- [x] Ensure keystore files and local signing property files are ignored by git.
- [x] Document required signing inputs: keystore path, key alias, store password, key password.
- [x] Verify that a missing signing config fails with a clear release-build error instead of silently using debug signing.

### Task 3: Huawei/CN Compliance Review

**Files:**
- Modify: `privacy_policy.html`
- Modify: `support.html`
- Modify: `eula.html`
- Modify: `PRIVACY.md`
- Modify: `EULA.md`
- Modify: `docs/huawei_appgallery_submission.md`

- [x] Align app name across privacy policy, support page, terms, Android label, and AppGallery metadata.
- [x] Confirm the privacy policy lists actual CN providers only: Qwen/Alibaba Cloud, Baidu OCR if enabled, Aliyun ASR if enabled, SMS provider, cloud sync backend, payment/会员 provider if enabled.
- [x] Remove or clearly mark services not active in CN, especially Apple, Google, Gemini, Finnhub, Google Vision, and Play Billing.
- [x] Confirm permissions are explained: microphone, camera, image access, network, and notification only if used.
- [x] Add Pangle/穿山甲广告 SDK disclosure after confirming the exact SDK name, developer entity, privacy policy link, compliance guide link, data categories, and purpose.
- [x] Confirm account deletion wording matches the in-app flow and backend behavior.
- [x] Add a Huawei reviewer note for financial-safety positioning: personal bookkeeping and asset tracking only, no investment advice, no收益承诺.

### Task 4: Pangle Ads Integration And Compliance

**Files:**
- Modify: `pubspec.cn.yaml`
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/cn/AndroidManifest.xml`
- Create/modify: `lib/services/pangle_ad_service.dart`
- Modify: ad placement UI files after product decision, likely `lib/features/accounting/presentation/pages/home_page.dart` and/or `lib/features/accounting/presentation/widgets/premium_vip_card.dart`
- Modify: `privacy_policy.html`
- Modify: `PRIVACY.md`
- Modify: `docs/huawei_appgallery_submission.md`
- Modify: `docs/android_release_checklist.md`

- [ ] Confirm commercial prerequisite: Pangle account, enterprise/authorized主体, contract status, app record, App ID, and code positions are ready.
- [x] Decide CN ad strategy before implementation: banner/native/interstitial/rewarded, free-user only or all users, and pages where ads will appear.
- [x] Choose the integration route: official Android SDK through a Flutter bridge, existing maintained Flutter plugin, or mediation platform. Prefer the smallest route that supports Huawei/CN release without pulling Google Play services.
- [x] Add CN-only dependency/configuration so INTL builds are not affected.
- [x] Initialize Pangle only after the user has agreed to privacy terms.
- [x] Add a user-facing path to disable personalized ads if personalized recommendation is enabled.
- [x] Add no-ad fallback for missing App ID, test mode, load failure, unsupported device, or reviewer builds.
- [x] Update privacy policy and SDK list with Pangle/穿山甲 data collection and purpose.
- [x] Update AppGallery reviewer notes with ad behavior, ad positions, and whether personalized ads are enabled.

### Task 5: Runtime Privacy Gate

**Files:**
- Inspect: `lib/features/accounting/presentation/pages/welcome_page.dart`
- Inspect: `lib/features/accounting/presentation/pages/phone_login_page.dart`
- Inspect: `lib/features/accounting/presentation/pages/home_page.dart`
- Inspect: `lib/services/pangle_ad_service.dart` after Task 4 exists.
- Modify relevant files only if consent behavior is not strict enough.

- [x] Verify whether any analytics, cloud, AI, OCR, SMS, ad SDK, or device identifiers run before the user explicitly agrees to the privacy policy.
- [x] If needed, add a first-launch privacy consent gate before guest login, phone login, analytics tracking, ad SDK initialization, and AI/OCR actions.
- [x] Add or update tests for the consent gate.
- [x] Verify that refusing consent leaves the app usable only in a no-collection state or exits cleanly.

### Task 6: Android Package Hygiene

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `tools/android_audit_cn_no_google.sh`
- Modify: `docs/android_release_checklist.md`

- [x] Confirm CN APK/AAB contains no Google sign-in, Play services, Firebase, Gemini, or Google Vision binaries.
- [x] Confirm CN APK/AAB contains only the intended Pangle/穿山甲 ad SDK artifacts and no unexpected mediation SDKs.
- [ ] Confirm permissions are limited to used CN features.
- [x] Confirm package name is final for Huawei: `com.aiaccountant.ai_accountant.cn`.
- [x] Confirm version is final for first Huawei submission: current baseline `1.4.1+1`.

### Task 7: Build And Local Verification

**Files:**
- Modify: `docs/huawei_appgallery_review_log.md`

- [ ] Run `make android-build-cn` to generate a signed release APK.
- [ ] Run `make android-audit-cn-no-google APK_PATH=<generated-apk>`.
- [ ] Run `make android-build-cn-aab` if Huawei submission uses App Bundle.
- [ ] Install the release APK on an Android device or emulator and verify launch, guest mode, phone login entry, settings, privacy policy, terms, account deletion entry, OCR entry, voice entry, export, ad loading, no-ad fallback, and personalized-ad toggle if enabled.
- [ ] Capture screenshots for AppGallery listing.

### Task 8: AppGallery Connect Submission Packet

**Files:**
- Create/modify: `docs/huawei_appgallery_submission.md`

- [ ] Prepare app name, short description, full description, category, keywords, version notes, support email, privacy URL, terms URL, and reviewer notes.
- [ ] Prepare permission usage explanations for AppGallery Connect.
- [ ] Prepare ad SDK disclosure and reviewer instructions for where ads appear.
- [ ] Prepare test account or reviewer instructions if phone login/SMS blocks review.
- [ ] Prepare compliance attachments checklist: APP备案号, ICP备案, 软件著作权, business license or personal developer identity, financial/non-financial statement, SDK list.

### Task 9: External Platform Tasks

**Files:**
- Modify: `docs/huawei_appgallery_review_log.md`

- [ ] Confirm Huawei developer account real-name verification is complete.
- [x] Confirm AppGallery Connect app record is created for `com.aiaccountant.ai_accountant.cn`.
- [ ] Confirm Pangle/穿山甲 developer account, enterprise/authorized主体, contract, app record, App ID, and ad code positions are approved or in test status. App/media ID `5827353` and first-release Banner ad slot `104073039` are created in test status.
- [ ] Confirm APP备案号 and ICP备案 status for mainland China release.
- [ ] Upload package and metadata to AppGallery Connect.
- [ ] Submit review.
- [ ] Record any rejection reason and patch the repo or metadata immediately.

---

## Current Known Blockers

- Release signing config has been added, and Gradle now fails clearly when signing values are missing.
- Pangle/穿山甲 client integration compiles in CN debug and launches on real device after unlock. GroMore initializes and requests ad slot `104073039`. The earlier `40029` was traced to requesting too soon after SDK start, before internal Pangle ADN initialization finished. The client now includes debug ADN details, template Banner sizing via `setExpressViewAcceptedSize`, and a delayed/retried Banner load path. Final real-device verification reached `104073039 -> pangle / 981713677`, loaded successfully, and logged `TTBannerView onRenderSuccess 渲染成功`.
- Huawei/CN submission still needs formal signed package generation.
- AppGallery project/app record is created: `财富记账本`, package `com.aiaccountant.ai_accountant.cn`, App ID `117736975`; AG Connect config is integrated at `android/app/src/cn/agconnect-services.json`.
- Huawei IAP automatic-renewal subscription product creation is blocked by Huawei backend access control, so CN first release changed to a one-time `非消耗型` lifetime ad-free product: `ai_wealth_tracker_lifetime_ad_free`. The product is created and activated in AppGallery Connect with China-only sales scope and CNY `28` price. A sandbox tester has been added manually and is signed in on the Motorola test phone. The earlier HMS Core update failure `102` was traced to first-run HMS dynamic kit loading; after reinstalling the APK with `installerPackageName=com.huawei.appmarket` and letting HMS Core finish loading `fwkit`/IAP components, real-device product query now succeeds and returns `¥28.00`. Purchase currently fails at Huawei create-order with `IAP_APP_NOT_EXISTED / 60002` because AGC `应用内支付服务` is still off and the developer console `商户服务` status is `未开通` with the domestic receiving account `审核中`; wait for merchant-service approval, enable IAP API, then retest purchase/restore/ad removal before submission.
- External items still need confirmation: Pangle account contract/settlement/ad-slot approval, APP备案, ICP备案/public policy URL hosting, software copyright or authorization materials.
