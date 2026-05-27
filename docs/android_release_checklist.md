# Android 发布检查清单（财富记账本 / AI Wealth Tracker 1.4.1）

> 目标：为 Android 原生复刻补齐 release 发布前可核对项。完成静态入口后再做打包/上传。

## 1. Android SDK 与构建前置

- **当前构建方式**：CN/INTL 两套 flavor 独立发布，建议执行 `flutter build appbundle --flavor ... --dart-define=APP_FLAVOR=... --release`。
- **JDK 状态（2026-05-16）**：已安装并配置 OpenJDK 17.0.19，Flutter `jdk-dir` 指向 `/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`，`flutter doctor -v` 已无问题。
- **常见阻塞**：若本地缺少 Android SDK / 命令行工具，构建会报 `flutter` 或 `java`/`sdkmanager` 相关错误，表现为“SDK 路径/版本未配置”。
- 本次复刻前请先确认：
  - `flutter doctor` 无关键红线（Android toolchain、JDK、Emulator 相关项通过）
  - Android SDK Platform 与 Build Tools 已按 `android/app/build.gradle.kts` 的 `compileSdk/targetSdk` 覆盖

## 2. 包名与签名

- **ApplicationId / namespace（主）**：`com.aiaccountant.ai_accountant`
- **独立应用 ID（flavor）**：
  - CN：`com.aiaccountant.ai_accountant.cn`
  - INTL：`com.aiaccountant.ai_accountant.intl`
- 发布签名（至少需确认）：
  - `release` signing key store 路径
  - `storePassword` / `keyPassword`
  - `keyAlias`
  - keystore 有效期与版本管理（变更是否同步到团队安全库）
- 发布构建已禁止继续使用 debug 签名。`release` 会读取以下任一配置来源：
  - 本地文件：`android/key.properties`（已被 git 忽略）
  - 环境变量：`AI_ACCOUNTANT_ANDROID_KEYSTORE_FILE`、`AI_ACCOUNTANT_ANDROID_STORE_PASSWORD`、`AI_ACCOUNTANT_ANDROID_KEY_ALIAS`、`AI_ACCOUNTANT_ANDROID_KEY_PASSWORD`
- `android/key.properties` 示例：
  ```properties
  storeFile=/absolute/path/to/upload-keystore.jks
  storePassword=...
  keyAlias=...
  keyPassword=...
  ```
- 若 release 构建缺少上述任一项，Gradle 会直接失败，避免误产出 debug-signed 包。
- CN 与 INTL 按两个完全独立应用管理：各自独立应用 ID、签名、上架渠道与版本历史。

## 3. Google OAuth / 登录相关（仅英文版 INTL）

中文版 CN 不配置 Google OAuth，不填写 Google/Gemini/Finnhub 等英文版专用配置。如英文版使用 `google_sign_in`，请在 Google Cloud Console 补充并落表：
- Android OAuth 2.0 Client 证书 SHA-1
- Android OAuth 2.0 Client 证书 SHA-256
- 客户端包名：`com.aiaccountant.ai_accountant.intl`
- 调试 / 发版 build variant 对应的签名证书指纹是否一致
- `.env` 中 `GOOGLE_SERVER_CLIENT_ID` 必填，用于 Android Google 登录的 server auth。
- `.env` 中 `GOOGLE_ANDROID_CLIENT_ID` 可选，仅作为 Android OAuth client 的文档/排查值；当前 Flutter `google_sign_in` Android 运行时不直接传入该值。

## 4. 华为 IAP / 应用内支付配置（CN 终身去广告）

- CN / 华为包使用华为 IAP Kit，不使用 Apple App Store 或 Google Play Billing。
- CN 首版改为一次性买断去广告，不使用自动续费订阅。
- 商品类型应选择 `非消耗型`，不是 `消耗型`：
  - `消耗型` 适合金币、次数包等会被用掉的商品。
  - `非消耗型` 适合终身权益、永久解锁、终身去广告。
- 在 AppGallery Connect 中创建商品并保持与客户端商品 ID 一致：
  - 终身去广告：`ai_wealth_tracker_lifetime_ad_free`
  - 已配置销售范围：中国大陆
  - 已配置价格：中国区 CNY `28`
- 当前 AppGallery Connect 状态：
  - 已创建项目和 Android 应用记录，包名为 `com.aiaccountant.ai_accountant.cn`，APP ID 为 `117736975`。
  - 已下载并接入 CN flavor 专用 `android/app/src/cn/agconnect-services.json`。
  - `项目设置 -> API管理 -> 应用内支付服务` 尚未真正开启。尝试开启时，AGC 提示需先开通商户服务并签署《华为商户服务协议》。
  - `管理中心 -> 商户服务` 当前显示服务状态 `未开通`、境内收款账户 `审核中`，页面提示审核时间约 `1-2 个工作日`。该状态会阻断 IAP 下单链路。
  - 商品管理中选择 `自动续期订阅` 会提示需先联系应用联运合作商务申请开通自动续费订阅型商品服务；已决定避开该流程，改用 `非消耗型` 终身去广告。
  - `非消耗型` 终身去广告商品已保存并激活，销售范围为中国大陆，价格为 CNY `28`。
- 华为 IAP 沙盒测试账号已由账号 owner 手动添加，真机已登录 `19560772181`。
- 已为当前 CN debug 测试包在 AGC `项目设置 -> 常规` 添加 SHA256 证书指纹；正式 release / AAB 构建前还必须添加最终上传签名证书指纹。
- 真机 IAP 查询验证状态：
  - 已通过 AppGallery 将 HMS Core 从 `6.15.6.312` 更新到 `6.15.6.332`，详情页显示“打开”而不是“更新”。
  - 打开 HMS Core 后已清理账号安全/通知授权前置弹窗，并确认沙盒账号已登录。
  - Debug 包使用 `adb install -i com.huawei.appmarket -r ...` 安装，确认 `installerPackageName=com.huawei.appmarket`，贴近 AppGallery 来源安装环境。
  - 首次触发商品查询时，HMS Core 曾弹出 `暂时无法更新，请稍后再试。（102）`，并在日志中出现 `com.huawei.hwid.core` 动态框架 `NoClassDefFoundError: com.huawei.gson.Gson`；随后 HMS 开始补齐/加载 `fwkit` 和 `IAP_APK[6.26.2.300]` 等动态组件。
  - 重新冷启动后商品查询已成功：`obtainProductInfo result=0`，客户端日志显示 `queryProductDetails found=1`，商品 `ai_wealth_tracker_lifetime_ad_free` 返回价格 `¥28.00` / `CNY` / `rawPrice=28.0`。
  - 发起购买时能进入华为创建订单链路，但返回 `responseMessage = IAP_APP_NOT_EXISTED`、`subErrCode = 101`、`exitService = 60002`。结合 AGC 后台状态，当前根因是商户服务/IAP API 未完成开通，而不是客户端商品 ID、包名或价格配置错误。
  - 仍需在华为/荣耀真机或 AppGallery Connect 云测试资源上验证完整购买、恢复购买、支付后去广告；当前 Motorola PRC ROM 已可验证商品查询，但不能作为 Huawei IAP 支付链路最终验收设备。
  - AppGallery Connect `质量 -> 云调试` 已检查：当前账号显示剩余优惠时长 `0` 分钟、套餐余额 `0` 分钟、按量付费未开通、机型列表 `0` 条。
  - AppGallery Connect `质量 -> 云测试` 可见今日赠送时长 `600` 分钟；如要上传 APK 到云端测试，需先确认是否允许把当前测试包上传到华为云测试。
- 服务端需要校验华为 IAP 返回的 `purchaseToken` / 票据，再写入云端会员状态。
- 客户端接入状态：
  - CN Android 通过 `HuaweiIapVipGateway` 使用 Huawei IAP Kit 查询非消耗型商品、发起购买、恢复购买。
  - 购买/恢复数据会保留华为 `InAppPurchaseData` JSON、`inAppDataSignature`、`receipt_source=huawei_iap`、`store_provider=huawei`，供云端验签。
  - 终身去广告购买成功后，本地权益写为 `VipType.lifetime`，采用远期有效期表达永久权益。
  - `VipService.removesAds == isVip`，终身权益有效时首页 Banner 不初始化、不请求、不展示。
  - `HuaweiIapVipGateway` 已移除会触发设备更新流的 `isEnvReady` 前置等待，商品查询/购买/恢复购买都加了 20 秒超时，避免 HMS 运行时卡住导致订阅页永久加载。
  - 会员购买弹窗已增加商品加载失败兜底：若 HMS/IAP 查询失败，按钮不再永久停留在“价格加载中”，会提示用户打开或更新 HMS Core 后重试，并提供重试入口。
  - `flutter test test/vip_service_platform_test.dart test/pangle_ad_service_test.dart` 通过。
  - `flutter analyze` 通过。
  - `./gradlew :app:assembleCnDebug --stacktrace` 通过。
  - 接入 `com.huawei.agconnect` 后，CN Debug 构建确认使用 `android/app/src/cn/agconnect-services.json`。

## 5. 穿山甲广告配置（CN）

- 首版接入方式：穿山甲 GroMore 融合 SDK + Flutter PlatformView 桥接，不引入 Google Play services。
- 穿山甲 App / 媒体 ID：`5827353`
- 首页底部 Banner 广告位 ID：`104073039`
- 旧开屏广告位 ID：`104073928`，首版暂不接入。
- CN-only 原生配置：
  - `android/build.gradle.kts` 添加 Pangle Maven 仓库。
  - `android/app/build.gradle.kts` 使用 `cnImplementation("com.pangle.cn:mediation-sdk:7.6.1.1")`。
  - `android/app/src/cn/AndroidManifest.xml` 添加穿山甲 `TTFileProvider`。
  - `android/app/src/cn/kotlin/.../PangleAdsRegistrar.kt` 注册广告 MethodChannel 与 Banner PlatformView。
- 广告请求条件：
  - 仅 CN flavor。
  - 仅 Android。
  - 用户已同意隐私政策。
  - 用户未购买终身去广告权益。
  - App ID / 广告位 ID 非空。
- 个性化广告关闭路径：设置 → 个性化广告推荐。
- 验证状态：
  - `flutter analyze` 通过。
  - `flutter test test/ad_preferences_service_test.dart test/vip_service_platform_test.dart test/pangle_ad_service_test.dart` 通过。
  - `./gradlew :app:assembleCnDebug --stacktrace` 通过，已验证穿山甲原生桥、华为 IAP 与 CN flavor 可编译。
  - `app-cn-debug.apk` 已成功安装并冷启动到真机 `ZY22LDKR8L`。
  - 真机已验证应用不再因 Pangle provider 崩溃，GroMore SDK 初始化成功，广告位 `104073039` 请求会进入瀑布流。
  - 已补充 GroMore ADN 诊断参数 `show_adn_load_error_detail=true`，真机复测确认 `onError` 返回底层 ADN JSON 明细。
  - Banner 模板渲染请求已补 `setExpressViewAcceptedSize(widthDp,heightDp)`。
  - 已加入 Banner 首次加载延迟与最多 3 次重试，避免 `TTAdSdk.start` 成功后过早请求导致 Pangle ADN 初始化窗口内返回 `40029`。
  - 真机最终复测通过：`104073039 -> pangle / 981713677` 请求成功，并出现 `TTBannerView onRenderSuccess 渲染成功`。

## 6. Play Billing 配置（仅英文国际版如启用会员/付费）

- 检查 `in_app_purchase` 已在应用层接入并在发行文档中列出付费 SKU。
- 英文版上传前在 Google Play Console Billing 中确认：
  - 商品 ID：
    - 月度订阅：`ai_wealth_tracker_monthly`
    - 年度订阅：`ai_wealth_tracker_yearly`
  - 商品类型（订阅/一次性）
  - 价格与税费地区
  - 上架状态（已发布/草稿）
  - 包名绑定：`com.aiaccountant.ai_accountant.intl`
- 发起测试前先做内部测试轨道，确认支付回调与收据流程完整。
- 服务器端仍需补 Play purchase token 验签；客户端目前会把 Google Play 返回的 `serverVerificationData` 作为过渡凭据回传。

## 7. 权限与原生配置验收

本次变更已加入以下发布验收项：

- `android/app/src/main/AndroidManifest.xml`
  - `android.permission.INTERNET`
  - `android.permission.RECORD_AUDIO`
  - `android.permission.CAMERA`
  - `android.speech.RecognitionService` package visibility query
  - `android:allowBackup="true"`
  - `android:fullBackupContent="@xml/secure_storage_backup_rules"`
- `android/app/src/main/res/xml/secure_storage_backup_rules.xml`
  - 排除 `domain="sharedpref"` 下的 Flutter secure storage 相关文件

补充说明：

- Android 13 相关图片读取权限在当前实现按“保守可发布”先给出：
  - `READ_MEDIA_IMAGES`
  - `READ_EXTERNAL_STORAGE`（`android:maxSdkVersion="32"`）
- 若产品后续确认完全不走图片导入/拍照/图库场景，可在主 manifest 评估移除并同步 Play 合规说明。

## 8. 构建命令（独立版本）

- 中文版：
  - `flutter build appbundle --flavor cn --dart-define=APP_FLAVOR=cn --release`
- 国际版：
  - `flutter build appbundle --flavor intl --dart-define=APP_FLAVOR=intl --release`
- 调试场景可改为：
  - `flutter build apk --flavor cn --dart-define=APP_FLAVOR=cn --release`
  - `flutter build apk --flavor intl --dart-define=APP_FLAVOR=intl --release`

## 9. 可执行静态检查入口

- 执行：`make android-static-check`
- 该命令用于不依赖 Android SDK 的静态校验，覆盖：
  - release 权限是否齐备
  - `speech_to_text` 查询项是否存在
  - 备份排除文件是否就位
