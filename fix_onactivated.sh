
#!/bin/zsh
cd /Users/phil/.openclaw/workspace-feishu/agent-forge/ai_accountant
# 替换 1: _showVipPurchaseSheet 中的 builder
sed -i '' -e 's/builder: (ctx) => _VipPurchaseSheet(onActivated: () {.*\});/builder: (ctx) => const _VipPurchaseSheet(),/g' lib/features/accounting/presentation/pages/settings_page.dart
# 替换 2: ElevatedButton 里的 if (success) widget.onActivated();
sed -i '' -e 's/if (success) widget.onActivated();//g' lib/features/accounting/presentation/pages/settings_page.dart
# 替换 3: 恢复购买里的 widget.onActivated();
sed -i '' -e 's/widget.onActivated();//g' lib/features/accounting/presentation/pages/settings_page.dart

echo "Done"
