# FC 部署说明

## 部署包

- 仓库内部署包：`functions/index.py.zip`
- 主入口源码：`functions/index.py`

## 推荐启动方式

- 启动命令：`python3 index.py`
- 监听端口：环境变量 `FC_FUNCTION_PORT`，默认 `9000`

## 必需环境变量

### TableStore / 阿里云
- `ALIYUN_ACCESS_KEY_ID`
- `ALIYUN_ACCESS_KEY_SECRET`
- `OTS_INSTANCE_NAME`
- `OTS_REGION`，默认 `cn-hangzhou`
- `OTS_TABLE`，默认 `accounting_entries`
- `ASSET_TABLE`，默认 `asset_items`
- `STOCK_POSITIONS_TABLE`，默认 `stock_positions`
- `VIP_TABLE`，默认 `vip_profiles`

### 短信
- `ALIYUN_SMS_SIGN_NAME`
- `ALIYUN_SMS_TEMPLATE_CODE`

### Apple 订阅校验
- `APP_STORE_SHARED_SECRET`
- `APP_STORE_BUNDLE_ID`，默认 `com.phil.AIAccountant`
- `APP_STORE_SERVER_ISSUER_ID`
- `APP_STORE_SERVER_KEY_ID`
- `APP_STORE_SERVER_PRIVATE_KEY` 或 `APP_STORE_SERVER_PRIVATE_KEY_PATH`
- `APP_STORE_SERVER_API_ENV`，默认 `production`
- `APP_STORE_ROOT_CERT_PEM`，建议配置 Apple Root CA PEM
- `APP_STORE_REQUIRE_TRUSTED_JWS=true`，配置 root cert 后建议开启

## 前端需要对应配置

- App `.env` / `ios/Runner/.env` 里确保：
  - `ALIYUN_FC_API=<你的 FC HTTP 地址>`
- 不要在 App 端配置或暴露 `APP_STORE_SHARED_SECRET`、App Store Server API 私钥。

## App Store Connect 配置

- App Store Server Notifications V2 URL：
  - `https://<你的 FC HTTP 域名>/app-store/notifications/v2`
- 后端会用 `signedPayload` 校验通知，并通过 `appAccountToken` / `transaction_id` / `original_transaction_id`
  映射回 `vip_profiles`。
- 如果通知先到但本地还没完成 `/vip/sync`，后端会返回 200 并记录未映射日志，避免 Apple 持续重试。

## 部署后最小检查

### 1. 健康检查
访问：
- `GET /health`

期望：
- 返回 `status=ok`
- 能看到 OTS 相关环境变量已加载

### 2. VIP 环境识别日志
订阅成功后，查看 FC 日志，应能看到类似：
- `[VIP] /vip/sync user=... has_receipt=True`
- `[VIP] Apple verify production status=...`
- 或 `[VIP] Apple verify sandbox status=0`
- `[VIP] /vip/sync saved server profile={...}`
- `[AppStore] notification saved user=... type=...`
- `[VIP] /vip/sync saved profile={'vip_environment': 'sandbox' ...}`

如果仍是 `unknown`，优先检查：
- `APP_STORE_SHARED_SECRET` 是否已配置到 FC
- FC 是否已部署到最新 `functions/index.py`
- Apple verify 请求是否超时或失败
- App Store Server API issuer/key/private key 是否已配置到 FC
- App Store Server Notifications V2 URL 是否已在 App Store Connect 指向 `/app-store/notifications/v2`

## 当前这版修复点

- 主入口已统一为 OTS 版本 `functions/index.py`
- 已移除重复文件 `functions/index_ots_base.py`
- Apple receipt 校验已支持 `21007 -> sandbox` 回退
- `vip_environment` 会随 receipt 校验结果写入 `vip_profiles`
- 已增加定位日志，便于排查 `unknown`
- 已接入 App Store Server API 主动查询 `/vip/refresh`
- 已接入 App Store Server Notifications V2 `/app-store/notifications/v2`
- 客户端同步会带匿名 `app_account_token` 与交易 ID，便于后端接收 Apple 通知后更新订阅状态
