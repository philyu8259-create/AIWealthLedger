# 财富记账本 / AI Wealth Tracker Android

> 技术栈：Flutter + flutter_bloc + go_router + Clean Architecture
> 云端：阿里云函数计算接口（`ALIYUN_FC_API`）
> AI / OCR：按区服与 `.env` 配置启用
> 产品形态：Android 独立双 flavor（CN / Intl）
> 状态：当前仓库为本地最新代码，运行能力取决于 `.env` 凭据与后端配置

## 技术栈

| 组件 | 技术 |
|------|------|
| 框架 | Flutter |
| 状态管理 | flutter_bloc |
| 路由 | go_router |
| 架构 | Clean Architecture（domain / data / presentation） |
| DI | get_it |
| 云端同步 | 阿里云函数计算接口 + `cloud_service.dart` |
| 中国区文本 AI | 通义千问 / `qwen_service.dart` |
| 英文版文本 AI | Gemini / `gemini_input_parser_service.dart` |
| 中国区 OCR | 百度 OCR / OCR.space / 阿里云 OCR |
| 英文版 OCR | Google Vision |
| 美股行情（intl） | Finnhub |

## 项目结构

```text
lib/
├── app/
│   ├── app.dart
│   ├── app_flavor.dart
│   └── router.dart
├── core/
│   ├── formatters/
│   ├── theme/
│   └── usecases/
├── features/accounting/
│   ├── data/
│   │   ├── datasources/
│   │   │   ├── cloud_asset_datasource.dart
│   │   │   ├── cloud_sync_account_datasource.dart
│   │   │   ├── mock_account_entry_datasource.dart
│   │   │   └── mock_asset_datasource.dart
│   │   ├── models/
│   │   └── repositories/
│   ├── domain/
│   │   ├── entities/
│   │   ├── repositories/
│   │   └── usecases/
│   └── presentation/
│       ├── bloc/
│       ├── pages/
│       └── widgets/
├── l10n/
├── main.dart
└── services/
    ├── cloud_service.dart
    ├── config_service.dart
    ├── qwen_service.dart
    ├── gemini_input_parser_service.dart
    ├── gemini_spending_prediction_service.dart
    ├── google_vision_receipt_ocr_service.dart
    ├── aliyun_asr_service.dart
    ├── aliyun_ocr_service.dart
    ├── baidu_ocr_service.dart
    ├── stock_service.dart
    └── vip_service.dart
```

## 运行

```bash
flutter pub get
flutter analyze
cp .env.example .env
flutter run --flavor cn --dart-define=APP_FLAVOR=cn
```

如果你使用 FVM，可以直接固定到当前仓库推荐版本：

```bash
fvm use
fvm flutter pub get
```

### Android 独立构建（cn / intl）

构建前先执行 `./tools/select_app_variant.sh cn` 或 `./tools/select_app_variant.sh intl` 切换依赖清单；脚本会同步对应的 `pubspec.<variant>.lock` 到 `pubspec.lock`，并在 `flutter pub get` 后写回该文件，保持两套 lock 独立更新。

当前 Android 使用独立 flavor 构建：

- 中文版：`cn`
- 英文版：`intl`

```bash
flutter run --flavor cn --dart-define=APP_FLAVOR=cn
flutter run --flavor intl --dart-define=APP_FLAVOR=intl
```

Release 构建（可按发布场景切换 apk / appbundle）：

```bash
flutter build apk --release --flavor cn --dart-define=APP_FLAVOR=cn
flutter build apk --release --flavor intl --dart-define=APP_FLAVOR=intl
flutter build appbundle --release --flavor cn --dart-define=APP_FLAVOR=cn
flutter build appbundle --release --flavor intl --dart-define=APP_FLAVOR=intl
```

- CN 发布时可继续补充 `--dart-define`：

  `QWEN_API_KEY`、`BAIDU_AK`、`BAIDU_SK`、`OCR_SPACE_API_KEY`、
  `ALIYUN_FC_API`、`ZHITU_API_TOKEN`、
  `ALIYUN_ACCESS_KEY_ID`、`ALIYUN_ACCESS_KEY_SECRET`、
  `ALIYUN_ASR_APP_KEY`。

  示例：

```bash
flutter build appbundle --release --flavor cn \
  --dart-define=APP_FLAVOR=cn \
  --dart-define=QWEN_API_KEY=... \
  --dart-define=BAIDU_AK=... \
  --dart-define=BAIDU_SK=... \
  --dart-define=OCR_SPACE_API_KEY=... \
  --dart-define=ALIYUN_FC_API=... \
  --dart-define=ZHITU_API_TOKEN=... \
  --dart-define=ALIYUN_ACCESS_KEY_ID=... \
  --dart-define=ALIYUN_ACCESS_KEY_SECRET=... \
  --dart-define=ALIYUN_ASR_APP_KEY=...
```

独立应用标识（按 Gradle 当前配置）：

- CN：`com.aiaccountant.ai_accountant.cn`
- INTL：`com.aiaccountant.ai_accountant.intl`

## 功能状态

| 功能 | 当前状态 |
|------|------|
| 首页记账（AI 文字 / 快捷） | ✅ 完成 |
| 🎤 语音记账（ASR） | ✅ 已接入，需配置阿里云语音相关凭据 |
| 📷 OCR 票据记账 | ✅ 已接入，需按区服配置对应 OCR 凭据 |
| 账单列表（筛选 / 滑动删除） | ✅ 完成 |
| 月度报表（支出分布 / 排名） | ✅ 完成 |
| 预测页 / AI 分析 | ✅ 已接入，需按区服配置对应 AI 凭据 |
| 资产页 | ✅ 完成，intl 美股行情需 `FINNHUB_API_KEY` |
| 设置页 | ✅ 完成 |
| flutter_bloc 状态管理 | ✅ 完成 |
| go_router 路由 | ✅ 完成 |
| get_it DI | ✅ 完成 |
| 本地 Mock 数据 | ✅ 完成 |
| 云端同步接口 | ✅ 已接入，需配置 `ALIYUN_FC_API` 与后端能力 |

## 环境变量

当前项目按两个独立 App 维护配置。发布/CI 场景建议通过 `--dart-define` 注入敏感配置，避免 `.env` 文件误入 APK。

先复制模板：

```bash
cp .env.cn.example .env      # 中文版
# 或
cp .env.intl.example .env    # 英文版
```

CN 打包场景可额外在命令中加上 `--dart-define`，例如（命令仅为示例）：

```bash
flutter build appbundle --release --flavor cn \
  --dart-define=APP_FLAVOR=cn \
  --dart-define=QWEN_API_KEY=...
```

### 英文版（intl）

```bash
GEMINI_API_KEY=
GOOGLE_VISION_API_KEY=
FINNHUB_API_KEY=
GOOGLE_IOS_CLIENT_ID=
GOOGLE_SERVER_CLIENT_ID=
GOOGLE_IOS_REVERSED_CLIENT_ID=
GOOGLE_ANDROID_CLIENT_ID=
```

- `GEMINI_API_KEY`：英文版文本记账解析、预测
- `GOOGLE_VISION_API_KEY`：英文版票据 OCR
- `FINNHUB_API_KEY`：英文版美股搜索与行情
- `GOOGLE_SERVER_CLIENT_ID`：英文版 Google 登录必需的 Web Client ID，Android 也依赖它
- `GOOGLE_IOS_CLIENT_ID` / `GOOGLE_IOS_REVERSED_CLIENT_ID`：iOS Google 登录配置
- `GOOGLE_ANDROID_CLIENT_ID`：Android OAuth client 记录项，便于和包名、SHA-1/SHA-256 配置核对

### 中国区行情

```bash
ZHITU_API_TOKEN=
```

- `ZHITU_API_TOKEN`：中国区 A 股搜索与行情

### 云端接口

```bash
ALIYUN_FC_API=
```

- `ALIYUN_FC_API`：账单、资产、VIP 等云端接口基地址

### 中国区 AI / OCR

```bash
QWEN_API_KEY=
BAIDU_AK=
BAIDU_SK=
OCR_SPACE_API_KEY=
```

- `QWEN_API_KEY`：文本 AI 解析 / 预测
- `BAIDU_AK` / `BAIDU_SK`：百度 OCR
- `OCR_SPACE_API_KEY`：OCR.space 备用 OCR

### 阿里云

```bash
ALIYUN_ACCESS_KEY_ID=
ALIYUN_ACCESS_KEY_SECRET=
ALIYUN_ASR_APP_KEY=
```

- `ALIYUN_ACCESS_KEY_ID` / `ALIYUN_ACCESS_KEY_SECRET`：阿里云能力接入
- `ALIYUN_ASR_APP_KEY`：阿里云语音识别

## 说明

- 如果 `FINNHUB_API_KEY` 未配置，英文版资产页会保持“美股接入中”并阻止股票新增 / 刷新。
- 如果 `ZHITU_API_TOKEN` 未配置，中国区 A 股搜索与行情会保持不可用或仅显示本地缓存数据。
- 如果英文版的 `GEMINI_API_KEY` 或 `GOOGLE_VISION_API_KEY` 未配置，对应 AI / OCR 能力会表现为不可用，而不会伪装回退到中国区 provider。
- 如果中国区 `QWEN_API_KEY`、OCR 或阿里云凭据未配置，对应能力会按当前代码路径降级或不可用。
- 显式 CN 构建会忽略 Google/Gemini/Finnhub 等英文版专用配置；显式 INTL 构建会忽略通义千问、百度 OCR、智兔和阿里云 ASR 等中文版专用配置。
- App Store shared secret / Server API private key 只允许配置在后端函数环境变量中，不能放入 App `.env` 或客户端包体。
- 本仓库已经移除 `.env`、`ios/Runner/.env`、`tmp/` 等本地敏感或临时内容，不会上传这些文件。

## 模式解析规则（按 flavor 锁定）

这是独立 Android 双 flavor 结构：

- CN flavor：`APP_FLAVOR=cn`，默认写入 `app_mode=cn`，中文界面、标题与能力按 CN 链路
- INTL flavor：`APP_FLAVOR=intl`，默认写入 `app_mode=intl`，英文界面、标题与能力按英文版链路

- 每个 flavor 首次启动后都会将 `app_mode` 与本地 locale/currency 按 flavor 默认值落盘；
  即使系统语言变化，也不会跨 flavor 回退到另一套链路。

## 推荐协作方式

为了避免你本地正在调试的目录和 Codex 的改动互相干扰，推荐使用独立 worktree：

```bash
git switch main
git pull origin main
git worktree add "../AI Wealth Tracker-codex-<task>" -b codex/<task> origin/main
```

这样你可以继续在主目录里手动调试，Codex 则在独立 worktree 中实现、验证和提交任务。

## 工程护栏

仓库现在包含一组最小但稳定的维护入口：

- `.fvmrc`：锁定推荐 Flutter 版本 `3.41.6`
- `Makefile`：统一 `bootstrap`、`analyze`、`test`、`ci`、`ios-build-check`
- `.github/workflows/flutter-ci.yml`：在 GitHub 上自动运行 `flutter pub get`、`flutter analyze`、`flutter test`
- `build_check.sh`：改为基于仓库相对路径执行，不再依赖某台机器上的旧绝对路径

## 相关文档

- `国际版认证剩余配置清单.md`
- `国际版真机联调清单.md`
- `国际版真机联调执行记录.md`
