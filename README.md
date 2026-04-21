# AI财富账本

> 技术栈：Flutter + flutter_bloc + go_router + Clean Architecture
> 云端：阿里云函数计算（已接入）
> AI：阿里通义（ASR ✅ 已接入 | OCR ✅ 已接入 | 通义 Key 待配置）
> 状态：本地 Mock 运行中，CloudBase 等凭据到位

## 技术栈

| 组件 | 技术 |
|------|------|
| 框架 | Flutter 3.41 |
| 状态管理 | flutter_bloc |
| 路由 | go_router |
| 架构 | Clean Architecture（domain/data/presentation） |
| DI | get_it |
| 云端 | 腾讯云 CloudBase `cloudbase_ce` ✅ |
| 语音识别 | 阿里云 ASR ✅ 已接入 |
| OCR 票据识别 | 阿里云 OCR ✅ 已接入 |
| AI 语义解析 | 通义千问 ⏳ 等 Key |

## 项目结构

```
lib/
├── main.dart
├── app/
│   ├── app.dart                 # BlocProvider + MaterialApp.router
│   └── router.dart              # go_router 底部 Tab 路由
├── core/usecases/
│   └── usecase.dart            # UseCase 基类
├── features/accounting/
│   ├── domain/
│   │   ├── entities/           # AccountEntry / CategoryDef
│   │   ├── repositories/       # AccountEntryRepository 接口
│   │   └── usecases/         # GetEntriesByMonth / AddEntry / DeleteEntry
│   ├── data/
│   │   ├── datasources/
│   │   │   ├── i_account_entry_datasource.dart  # 统一接口
│   │   │   ├── cloudbase_account_datasource.dart # CloudBase 实现
│   │   │   └── mock_account_entry_datasource.dart # Mock 实现
│   │   ├── models/
│   │   │   └── account_entry_model.dart
│   │   └── repositories/
│   └── presentation/
│       ├── bloc/              # AccountBloc + Events + States
│       └── pages/             # Home / Transactions / Reports / Settings
└── services/
    ├── cloudbase_service.dart  # CloudBase 服务封装
    ├── qwen_service.dart       # 通义千问 AI 语义解析
    ├── aliyun_asr_service.dart # 阿里云 ASR 语音识别
    ├── aliyun_ocr_service.dart # 阿里云 OCR 票据识别
    └── injection.dart          # get_it DI 容器
```

## 运行

```bash
flutter pub get
flutter analyze    # 应为 0 errors
flutter run        # 本地 Mock 运行
```

环境变量建议先从模板复制：

```bash
cp .env.example .env
```

## 功能进度

| 功能 | 状态 |
|------|------|
| 首页记账（AI 文字/快捷） | ✅ 完成 |
| 🎤 语音记账（ASR） | ✅ 已接入（等 Nova 配置 AccessKey） |
| 📷 OCR 票据记账 | ✅ 已接入（等 Nova 配置 AccessKey） |
| 账单列表（筛选/滑动删除） | ✅ 完成 |
| 月度报表（支出分布/排名） | ✅ 完成 |
| 设置页 | ✅ 完成 |
| flutter_bloc 状态管理 | ✅ 完成 |
| go_router 路由 | ✅ 完成 |
| get_it DI | ✅ 完成 |
| 本地 Mock 数据 | ✅ 完成 |
| CloudBase 云端集成 | ⏳ 等 Nova 配置凭据 |
| 通义千问 AI 预算建议 | ⏳ 等 Nova 配置 API Key |

## 待配置凭据

```
CloudBase:
  envId: phil-1982-8g6loclhc49b392d
  appAccessKey: （等 Nova 提供）
  appAccessVersion: （等 Nova 提供）

阿里云:
  AccessKey ID: （等 Nova 提供）
  AccessKey Secret: （等 Nova 提供）
  ASR AppKey: hCRcN0lEbeU7BhL9 ✅ 已就绪
  OCR: 共用 AccessKey ✅
  通义千问 API Key: （等 Nova 申请）
```

配置到位后，更新对应 service 文件中的凭据即可启用云端/AI 功能。

## 国际版新增环境变量

当前 intl 相关能力改为直接读取 `.env`：

```bash
GEMINI_API_KEY=
GOOGLE_VISION_API_KEY=
FINNHUB_API_KEY=
```

- `GEMINI_API_KEY`：intl 文本记账解析、消费预测
- `GOOGLE_VISION_API_KEY`：intl 票据 OCR
- `FINNHUB_API_KEY`：intl 美股搜索与行情

说明：
- 如果 `FINNHUB_API_KEY` 未配置，国际版资产页会继续显示“美股接入中”，并阻止新增/刷新股票，避免误打旧的 A 股数据源。
- 如果 `GEMINI_API_KEY` / `GOOGLE_VISION_API_KEY` 未配置，国际版 AI / OCR 会表现为不可用，而不是回退到国内 provider 伪装运行。

## 国际版联调文档

- `国际版认证剩余配置清单.md`
- `国际版真机联调清单.md`
