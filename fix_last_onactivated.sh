
#!/bin/zsh
cd /Users/phil/.openclaw/workspace-feishu/agent-forge/ai_accountant
# 找到第 1360 行附近的内容，替换 builder 部分
# 我们用行号定位：从第1364行到第1374行之间的内容
sed -i '' -e '1364,1374c\      builder: (ctx) =&gt; const _VipPurchaseSheet(),' lib/features/accounting/presentation/pages/settings_page.dart
echo "Done"
