# AI财富账本国际版任务拆单

## 目标
基于《AI财富账本国际版改造总结.md》，将国际版改造拆成可执行任务，供 Forge 按阶段推进。

---

## Phase 1：基础底座

### 1.1 Flavor / Profile 架构
- [ ] 新增 `cn` / `intl` 双 flavor 或 profile
- [ ] 建立启动时 profile 注入机制
- [ ] 确保中文与国际版 provider、登录、股票能力可隔离配置

**验收**
- 可分别启动 cn / intl
- 两个 flavor 配置互不污染

### 1.2 LocaleProfile / CapabilityProfile
- [ ] 定义 `LocaleProfile`
- [ ] 定义 `CapabilityProfile`
- [ ] 页面层改为统一读取 profile，不再直接写死 provider / 市场判断

**验收**
- 页面不再直接判断中文链路/国际链路
- 关键页面通过 profile 正常渲染

### 1.3 i18n 与 formatter 底座
- [ ] 建立文案 key 体系
- [ ] 抽象日期格式、数字格式、货币格式
- [ ] 支持 `locale + countryCode + baseCurrency` 三层输入

**验收**
- 关键 formatter 可独立测试
- 中文展示不退化

### 1.4 数据模型升级
- [ ] 升级 `UserProfile`
- [ ] 升级 `AccountEntry`
- [ ] 升级 `AssetAccount`
- [ ] 升级 `StockInstrument`
- [ ] 升级 `StockPosition`
- [ ] 新增 `FxRateSnapshot`

**验收**
- 新字段可正常序列化/反序列化
- 旧字段兼容读取

### 1.5 Migration 与回滚
- [ ] 实现本地 schema migration
- [ ] 设计云端 migration 方案
- [ ] 准备 migration 失败回滚策略
- [ ] 中文旧数据补默认值：locale/countryCode/baseCurrency 等

**验收**
- 老用户升级后可正常进入应用
- 旧账单、资产、A 股数据不丢失

---

## Phase 2：汇率系统

### 2.1 FX 服务抽象
- [ ] 定义 `FxRateService` 接口
- [ ] 支持 latest rate 查询
- [ ] 支持 historical rate 查询
- [ ] 统一 source / cache / fallback 结构

### 2.2 账单历史汇率快照
- [ ] 入账时写入 `baseAmount`
- [ ] 写入 `fxRate / fxRateDate / fxRateSource`
- [ ] 报表按历史快照聚合

### 2.3 资产实时重估
- [ ] 资产页按最新汇率计算 `baseBalance`
- [ ] 股票资产按最新汇率动态换算
- [ ] 不把派生 base value 当长期真值持久化

### 2.4 UI 展示
- [ ] 交易详情展示原币金额与折算金额
- [ ] 必要时显示汇率说明
- [ ] 报表按 base currency 展示

**验收**
- 非 base currency 账单入账正确
- 历史报表稳定
- 当前资产总览动态正确

---

## Phase 3：国际登录

### 3.1 认证底座
- [ ] intl flavor 接入 Firebase Auth
- [ ] 保持 cn flavor 现有手机号登录不变
- [ ] 不合并旧手机号体系与国际身份体系

### 3.2 登录能力
- [ ] Email OTP / Magic Link
- [ ] Google Sign-In
- [ ] Apple Sign In

### 3.3 用户初始化逻辑
- [ ] 新用户首次登录生成 `UserProfile`
- [ ] 初始化优先级：
  1. 用户首次手动选择
  2. system locale / device region
  3. fallback 到 `en-US + USD`

**验收**
- iOS / Android 登录闭环可用
- cn 不受影响
- intl 新用户 profile 初始化正确

---

## Phase 4：国际版 OCR + AI 记账

### 4.1 OCR 路由
- [ ] intl MVP 接 Google Vision OCR
- [ ] 预留 Google Document AI Expense Parser 增强位
- [ ] 定义 OCR 输出中间结构

### 4.2 AI 解析
- [ ] intl 接 Gemini 2.5 Flash
- [ ] 定义统一输出 schema：
  - amount
  - currency
  - merchant
  - date
  - categoryId
  - note
  - type
  - confidence

### 4.3 记账语义层
- [ ] 英文类目映射
- [ ] merchant normalization
- [ ] receipt / free text 双场景解析规则

**验收**
- 英文文本记账可用
- 英文拍照记账可用
- amount/currency/merchant/date 达到 MVP 可用标准

---

## Phase 5：国际版 UI

### 5.1 页面国际化
- [ ] welcome
- [ ] home
- [ ] transactions
- [ ] reports
- [ ] settings

### 5.2 国际默认资产模板
- [ ] cash
- [ ] checking
- [ ] savings
- [ ] credit_card
- [ ] brokerage

### 5.3 设置页能力
- [ ] baseCurrency 可手动设置
- [ ] locale / countryCode 配置入口

**验收**
- 英文 UI 无中文残留
- 长文案不破版
- 日期/数字/货币格式正确

---

## Phase 6：美股模块

### 6.1 抽象先行
- [ ] 定义 `UsStockProvider`
- [ ] 明确 search / quote / batch quote 接口

### 6.2 Provider 选型 checkpoint
- [ ] 对比 Polygon / Twelve Data / Finnhub
- [ ] 评估维度：
  - 接入速度
  - 成本
  - 批量报价能力
  - 稳定性
  - 搜索能力
  - 文档成熟度
- [ ] 定稿首个 provider

### 6.3 美股功能接入
- [ ] 美股搜索
- [ ] 单只报价
- [ ] 批量报价
- [ ] 美股持仓录入
- [ ] 资产页接入美股估值与盈亏

### 6.4 持仓规则
- [ ] quantity 改为 decimal
- [ ] MVP 至少支持 1 股粒度
- [ ] 预留 fractional share 扩展位

**验收**
- intl 可搜索并添加美股持仓
- 行情刷新、市值、盈亏计算可用
- cn A 股逻辑不受影响

---

## 横切任务

### A. API 细化
- [ ] Auth / Profile request/response 细稿
- [ ] Entries API 细稿
- [ ] FX API 细稿
- [ ] OCR / AI API 细稿
- [ ] Stocks API 细稿

### B. 观测与降级
- [ ] 请求日志
- [ ] provider 错误码归一
- [ ] 超时/重试策略
- [ ] fallback 策略
- [ ] 调用量统计
- [ ] AI/OCR 成本统计

### C. 合规文档
- [ ] Privacy Policy 国际版更新
- [ ] Terms of Use / EULA 更新
- [ ] 账号删除与数据删除说明
- [ ] 第三方数据处理说明

### D. QA 回归
- [ ] 中文版账单回归
- [ ] 中文版资产回归
- [ ] 中文版 A 股回归
- [ ] 国际登录测试
- [ ] 英文 OCR/AI 测试
- [ ] 多币种汇率测试
- [ ] 美股测试
- [ ] 弱网与降级测试

---

## 推荐执行顺序
1. Phase 1 基础底座
2. Phase 2 汇率系统
3. Phase 3 国际登录
4. Phase 4 国际版 OCR + AI
5. Phase 5 国际版 UI
6. Phase 6 美股模块
7. 横切任务收尾

---

## 当前建议
Forge 先从 **Phase 1 + Phase 2** 开始，这是整个国际版的地基。
在这两期稳定前，不建议直接并行推进美股和国际 UI 细节。