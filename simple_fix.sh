
#!/bin/zsh
cd /Users/phil/.openclaw/workspace-feishu/agent-forge/ai_accountant
# Step 1: Remove onActivated parameter from _VipPurchaseSheet class
sed -i '' -e 's/final VoidCallback onActivated;//g' lib/features/accounting/presentation/pages/settings_page.dart
sed -i '' -e 's/const _VipPurchaseSheet({required this.onActivated});/const _VipPurchaseSheet();/g' lib/features/accounting/presentation/pages/settings_page.dart
# Step 2: Remove onActivated parameter in _showVipPurchaseSheet method
sed -i '' -e 's/_VipPurchaseSheet(onActivated: () {.*});/const _VipPurchaseSheet(),/g' lib/features/accounting/presentation/pages/settings_page.dart
# Step 3: Remove "if (success) widget.onActivated();" and "widget.onActivated();"
sed -i '' -e 's/if (success) widget.onActivated();//g' lib/features/accounting/presentation/pages/settings_page.dart
sed -i '' -e 's/widget.onActivated();//g' lib/features/accounting/presentation/pages/settings_page.dart

echo "Simple fix done!"
