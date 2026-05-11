# Auto Bookkeeping Real Device Checklist

## 中文验收

- 使用真机安装 Debug 或 TestFlight 包，并确认系统语言分别切到中文和英文后，设置页入口文案会随 App 语言变化。
- 打开「快捷指令」App，确认能看到 `AI Auto Bookkeeping` 快捷指令动作，并创建流程：截取当前屏幕 -> 从图像提取文字 -> 运行 `AI Auto Bookkeeping`。
- 在微信、支付宝、银行账单或任意测试付款页完成截图流程，确认快捷指令会把提取文字传回 App。
- 触发 App 后，确认首页弹出 AI 解析结果；核对金额、商户、分类和支出方向，再点确认保存。
- 在设置 -> 辅助功能里分别配置轻点背面、辅助触控或 Siri 触发，确认每种入口都能运行同一条快捷指令。
- 断网或 AI 服务不可用时，确认 App 不会直接保存错误账单，而是停留在可重试或可编辑的状态。
- 验证隐私边界：App 不应后台读取微信、支付宝、短信、通知；只有主动运行快捷指令后，截图文字才进入解析。

## English Acceptance

- Install a Debug or TestFlight build on a real iPhone, then verify the setup entry follows the app language in both Chinese and English.
- Open the Shortcuts app, confirm the `AI Auto Bookkeeping` action is available, and create this flow: Take Screenshot -> Extract Text from Image -> Run `AI Auto Bookkeeping`.
- Run the shortcut from WeChat, Alipay, a bank receipt, or any test payment screen, and confirm the extracted text is passed back to the app.
- After the app opens, confirm the AI results sheet appears; review amount, merchant, category, and expense direction before saving.
- Configure Back Tap, AssistiveTouch, or Siri in Accessibility/Shortcuts, and confirm each trigger can run the same shortcut.
- When offline or when AI parsing is unavailable, confirm the app does not save an incorrect entry automatically and remains recoverable.
- Verify the privacy boundary: the app must not read WeChat, Alipay, messages, or notifications in the background; text is parsed only after the user runs the shortcut.

## Simulator Coverage

- The simulator can verify the App Intent build metadata, app routing, pending-text handoff, AI parsing sheet, and save flow.
- A real device is still required for the full iOS Shortcuts setup, Back Tap, AssistiveTouch, and Siri trigger validation.
