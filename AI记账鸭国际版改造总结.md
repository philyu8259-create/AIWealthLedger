# AI财富账本国际版改造总结

## 一、项目目标
在不破坏中文版现有体验的前提下，为 AI财富账本新增英文国际版能力，面向美国、英国、欧洲、澳洲等英文用户。

## 二、发布形态
采用：
- 单代码仓
- 双 flavor / profile
  - cn
  - intl

原因：
- 中文版与国际版在登录、OCR、AI、股票市场、默认货币等方面差异较大
- 双 flavor 更利于配置隔离、灰度发布、回归测试，并能更稳地保证中文版不退化

## 三、版本范围
### 中文版（cn）
- locale：zh-CN
- countryCode：CN
- baseCurrency：CNY
- 股票：仅支持 A 股
- OCR：现有中文方案
- AI：现有中文方案
- 登录：继续保留现有手机号登录

### 国际版（intl）
- locale：英文系，如 en-US / en-GB / en-AU
- countryCode：按用户国家初始化
- baseCurrency：按国家初始化，用户后续可手动修改
- 国家与默认币种初始化优先级：
  1. 用户首次手动选择
  2. 系统 locale / device region
  3. fallback 到 en-US + USD
- 股票：仅支持美股
- 登录：
  - Email OTP / Magic Link
  - Google Sign-In
  - Apple Sign In
- OCR：
  - MVP 主链路：Google Vision OCR + Gemini
  - 增强链路：Google Document AI Expense Parser
- AI：Gemini 2.5 Flash

### 非目标
- 本期不做港股
- 本期不做国际短信登录
- 本期不做券商导入
- 本期不做复杂税务与报税能力
- 本期不扩展中文版为 A/HK/US 多市场

## 四、关键配置模型
### 1. LocaleProfile
负责展示与默认值：
- locale
- countryCode
- baseCurrency
- dateFormat
- numberFormat
- currencyFormat

### 2. CapabilityProfile
负责能力与 provider：
- authProviders
- ocrProvider
- aiProvider
- stockMarketScope
- featureFlags

说明：
- 页面层只读取 LocaleProfile + CapabilityProfile
- 不允许在页面层到处写 cn / intl 判断

## 五、认证迁移策略
- cn flavor 继续保留现有手机号登录
- intl flavor 使用 Firebase Auth
- 本期不强行合并中文版旧手机号身份体系和国际版新身份体系

目的：控制复杂度，避免把国际版上线变成全量认证体系重构

## 六、核心技术原则
1. 页面层不直接判断 cn/int’l，只读 profile
2. App 不直连第三方 provider，统一走后端聚合层
3. 账单保存历史事实快照
4. 资产和股票按实时行情与实时汇率重估
5. 必须支持旧数据 migration，保证中文老用户无感升级

## 七、数据模型重点
### UserProfile
- userId
- locale
- countryCode
- baseCurrency
- authProviders
- stockMarketScope
- schemaVersion
- createdAt
- updatedAt

### AccountEntry（必须落历史汇率快照）
- originalAmount
- originalCurrency
- baseAmount
- baseCurrency
- fxRate
- fxRateDate
- fxRateSource
- merchantRaw
- merchantNormalized
- sourceType
- locale
- countryCode

### AssetAccount
建议持久化：
- balance
- currency
- locale
- countryCode

以下不建议长期持久化为真值，只做运行时计算或短缓存：
- baseBalance
- fxRateToBase

### StockInstrument
- symbol
- market
- exchange
- currency
- securityType
- lotSize
- timezone
- provider

### StockPosition
建议持久化：
- quantity
- costPrice
- costCurrency
- latestPrice
- latestPriceCurrency
- changePercent
- quoteTime
- quoteStatus

以下不建议长期持久化为真值：
- marketValueBase
- unrealizedPnlBase
- positionFxRate

### FxRateSnapshot
- baseCurrency
- quoteCurrency
- rate
- rateDate
- rateType（historical / latest）
- source

## 八、汇率系统设计
### 历史口径
用于账单：
- 入账时按交易日期获取历史汇率
- 写入 baseAmount、fxRate、fxRateDate、fxRateSource

### 实时口径
用于资产和股票：
- 打开资产页/总览页时拉最新汇率
- 动态计算 base currency 下总资产

### 最终效果
用户可看到：
- 原币金额
- 基准币折算金额
- 必要时展示汇率说明

## 九、OCR 与 AI 路线
### 国际版 OCR
MVP：
- Google Vision OCR
- Gemini 做结构化提取

增强：
- Google Document AI Expense Parser

### 国际版 AI
- Gemini 2.5 Flash
- 输出统一结构：
  - amount
  - currency
  - merchant
  - date
  - categoryId
  - note
  - type
  - confidence

## 十、股票系统设计
### 中文版
- 继续只支持 A 股
- 保持现有交互与 100 股整数倍规则

### 国际版
- 只支持美股
- quantity 模型改为 decimal
- MVP 至少支持 1 股粒度
- 为 future fractional share 预留能力

### Provider 策略
先抽象：
- UsStockProvider

候选：
- Polygon
- Twelve Data
- Finnhub

选择标准：
- 接入速度
- 成本
- 批量报价能力
- 稳定性
- 搜索能力
- 文档与 SDK 成熟度

要求：
- 由后端统一封装 /stocks/search、/stocks/quote、/stocks/quotes/batch
- 先完成抽象，再做 provider 选型和首个接入

## 十一、观测、降级与成本要求
必须具备：
- 请求日志
- provider 错误码归一
- 超时与重试策略
- fallback 策略
- 调用量统计
- 成本统计（至少覆盖 AI / OCR）

目标：
- 问题可排查
- provider 故障时可降级
- 能快速识别成本消耗来源

## 十二、执行阶段
### Phase 1：基础底座
- flavor/profile 架构
- LocaleProfile
- CapabilityProfile
- i18n key 体系
- formatter 抽象
- currency/date/number format
- schemaVersion / migrationVersion
- provider 抽象
- 数据模型升级
- 旧数据 migration

验收标准：
- 中文版可正常运行
- 老用户本地与云端数据升级成功
- 页面层已通过 profile 注入能力，不再直接依赖 provider

### Phase 2：汇率系统
- historical rate
- latest rate
- 账单历史快照
- 资产实时重估
- 原币/基准币展示

验收标准：
- 非 base currency 账单可正确入账
- 报表按历史快照稳定汇总
- 资产总览按最新汇率动态重估

### Phase 3：国际登录
- Firebase Auth
- Email OTP / Magic Link
- Google
- Apple
- 初始化 locale/country/baseCurrency

验收标准：
- iOS / Android 登录闭环可用
- 新用户 profile 初始化正确
- 不影响 cn flavor 现有手机号登录

### Phase 4：国际版 OCR + AI 记账
- Google Vision OCR
- Gemini parser
- 英文类目映射
- merchant normalization

验收标准：
- 英文文本记账可用
- 英文拍照记账可用
- amount / currency / merchant / date 抽取达到 MVP 可用标准

### Phase 5：国际版 UI
- welcome/home/transactions/reports/settings 国际化
- 国际版默认资产模板
- baseCurrency 可设置

验收标准：
- 英文 UI 无中文残留
- 多地区日期/数字/货币格式显示正确
- 关键页面布局在英文长文案下不破版

### Phase 6：美股模块
- UsStockProvider 抽象
- 候选 provider 对比
- 选定首个 provider
- 搜索/报价/批量报价
- 美股持仓录入
- 资产页接入美股估值

验收标准：
- 国际版可搜索并添加美股持仓
- 行情刷新、持仓市值、盈亏计算可用
- 中文版 A 股能力不受影响

## 十三、API 清单草案
### Auth / Profile
- POST /auth/session
- POST /auth/logout
- GET /me
- PATCH /me/preferences

### Entries
- GET /entries
- POST /entries
- PUT /entries/:id
- DELETE /entries/:id

### FX
- GET /fx/rate
- GET /fx/rates/latest
- GET /fx/rates/historical

### OCR / AI
- POST /ocr/parse
- POST /ai/receipt-parse
- POST /ai/text-parse

### Stocks
- GET /stocks/search
- GET /stocks/quote
- GET /stocks/quotes/batch
- GET /stock-holdings
- POST /stock-holdings
- PUT /stock-holdings/:id
- DELETE /stock-holdings/:id

说明：
- App 仅调用统一后端 API
- 第三方 provider key 不进入客户端
- API response 结构在正式开发前需再出 request/response 细稿

## 十四、前后端分工
### 前端
- flavor/profile 接入
- LocaleProfile / CapabilityProfile 消费
- i18n infra
- formatter
- 本地 migration
- 国际登录 UI
- 国际版记账 UI
- 国际版股票 UI

### 后端
- auth 聚合
- AI Router
- OCR Router
- FX Router
- UsStockProvider 抽象
- schema 兼容
- 缓存、限流、容错

### AI
- 英文 prompt
- OCR 结构化 prompt
- 类目映射
- merchant normalization
- confidence 规则

### QA
- 中文回归
- 汇率系统
- 国际登录
- 英文记账
- 美股行情
- 降级与弱网测试

## 十四、迁移与回滚策略
迁移要求：
- 本地 schema migration 必须可重复执行
- 云端 migration 必须先做备份，再做结构升级
- 中文老用户升级后默认补齐 locale/country/baseCurrency 等缺省值
- 老账单默认按既有中文口径补历史快照字段，不破坏现有展示与统计结果

回滚要求：
- 本地 migration 失败时可回退到上一个稳定 schema
- 云端 migration 必须保留备份与回滚脚本
- 新字段上线初期允许灰度读取，必要时可关闭新能力开关回退到旧链路

## 十五、合规文档更新
国际版上线前必须补齐：
- Privacy Policy 国际版更新
- Terms of Use / EULA 更新
- 账号删除与数据删除说明
- 第三方数据处理说明

## 十六、最终验收标准
### 中文版
- 账单正常
- 资产正常
- A 股正常
- 中文 OCR / AI 不退化

### 国际版
- 可注册登录
- 可初始化国家与基准币种
- 可英文文本记账
- 可英文拍照记账
- 可多币种账单入账
- 可按 base currency 汇总
- 可支持美股持仓与行情

## 十七、最终输出要求
Forge 最终需要交付：
1. 架构改造说明
2. 数据模型变更清单
3. migration 方案
4. API 设计清单
5. Phase 1 可运行版本
6. 中文回归报告
7. 风险与未完成项清单
8. 国际版 MVP 演示路径
9. 合规文档更新清单

---

结论：
这版方案已经达到可正式开工的程度，方向明确，边界清晰，能够在控制风险的前提下推进 AI财富账本国际版上线。