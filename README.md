# AI财富账本

> 技术栈：Flutter + flutter_bloc + go_router + Clean Architecture
> 云端：阿里云函数计算接口（`ALIYUN_FC_API`）
> AI / OCR：按区服与 `.env` 配置启用
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
| 国际版文本 AI | Gemini / `gemini_input_parser_service.dart` |
| 中国区 OCR | 百度 OCR / OCR.space / 阿里云 OCR |
| 国际版 OCR | Google Vision |
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
flutter run
```

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

当前项目通过 `.env` 驱动不同区服能力。

先复制模板：

```bash
cp .env.example .env
```

### 国际版（intl）

```bash
GEMINI_API_KEY=
GOOGLE_VISION_API_KEY=
FINNHUB_API_KEY=
GOOGLE_IOS_CLIENT_ID=
GOOGLE_SERVER_CLIENT_ID=
GOOGLE_IOS_REVERSED_CLIENT_ID=
```

- `GEMINI_API_KEY`：intl 文本记账解析、预测
- `GOOGLE_VISION_API_KEY`：intl 票据 OCR
- `FINNHUB_API_KEY`：intl 美股搜索与行情
- `GOOGLE_*`：intl Google 登录

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

### App Store

```bash
APP_STORE_SHARED_SECRET=
```

## 说明

- 如果 `FINNHUB_API_KEY` 未配置，intl 资产页会保持“美股接入中”并阻止股票新增 / 刷新。
- 如果 intl 的 `GEMINI_API_KEY` 或 `GOOGLE_VISION_API_KEY` 未配置，对应 AI / OCR 能力会表现为不可用，而不会伪装回退到中国区 provider。
- 如果中国区 `QWEN_API_KEY`、OCR 或阿里云凭据未配置，对应能力会按当前代码路径降级或不可用。
- 本仓库已经移除 `.env`、`ios/Runner/.env`、`tmp/` 等本地敏感或临时内容，不会上传这些文件。

## 相关文档

- `国际版认证剩余配置清单.md`
- `国际版真机联调清单.md`
- `国际版真机联调执行记录.md`
