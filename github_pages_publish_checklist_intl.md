# GitHub Pages 发布清单 | AI Wealth Ledger (intl)

目标：把以下 2 个页面发布到同一个公开站点目录下。

- `privacy_policy_en.html`
- `support_en.html`

目标 URL：

- `https://philyu8259-create.github.io/ai-accounting-privacy/privacy_policy_en.html`
- `https://philyu8259-create.github.io/ai-accounting-privacy/support_en.html`

---

## 待发布文件

从 `ai_accountant/` 目录取：

- `ai_accountant/privacy_policy_en.html`
- `ai_accountant/support_en.html`

---

## GitHub Pages 操作步骤

1. 打开承载隐私政策的仓库或 Pages 源目录
2. 确认已有 `privacy_policy_en.html`
3. 上传或提交以下文件：
   - `support_en.html`
4. 保持文件名不要改
5. 等待 GitHub Pages 发布完成
6. 用手机和桌面浏览器分别打开 2 个 URL 检查是否可访问

---

## 发布后验收

### 1. Support URL
应能打开：
```text
https://philyu8259-create.github.io/ai-accounting-privacy/support_en.html
```

### 2. Privacy URL
应继续正常：
```text
https://philyu8259-create.github.io/ai-accounting-privacy/privacy_policy_en.html
```

---

## App 内链接复核

代码当前 intl 链接：
- `privacyPolicyUrl` -> `privacy_policy_en.html`
- `termsOfServiceUrl` -> Apple Standard EULA

文件：
- `ai_accountant/lib/app/app_flavor.dart`

如果发布后 URL 可访问，App 内 Terms 链接会跳到 Apple 官方 EULA 页面。

---

## App Store Connect 需要填写的 URL

### Privacy Policy URL
```text
https://philyu8259-create.github.io/ai-accounting-privacy/privacy_policy_en.html
```

### Terms of Use / EULA URL
```text
https://www.apple.com/legal/internet-services/itunes/
```

### Support URL
```text
https://philyu8259-create.github.io/ai-accounting-privacy/support_en.html
```

---

## 最后提醒

- 不要把中文 `privacy_policy.html` 误填到 intl 版本
- 不要把失效的自建 EULA 链接误填到 intl 版本
- 如果 GitHub Pages 有缓存，更新后可等几分钟再验证
