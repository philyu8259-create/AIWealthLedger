
with open('/Users/phil/.openclaw/workspace-feishu/agent-forge/ai_accountant/lib/features/accounting/presentation/pages/settings_page.dart', 'r') as f:
    content = f.read()

# 1. 修改 _showVipPurchaseSheet 方法，移除 onActivated 参数
old1 = '''  void _showVipPurchaseSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) =&gt; _VipPurchaseSheet(onActivated: () {
        Navigator.pop(ctx);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('会员开通成功！感谢您的支持 🎉')),
        );
        // 刷新当前页
        context.go('/settings');
      }),
    );
  }'''
new1 = '''  void _showVipPurchaseSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) =&gt; const _VipPurchaseSheet(),
    );
  }'''
content = content.replace(old1, new1)

# 2. 修改 _VipPurchaseSheet 类，移除 onActivated 参数
old2 = '''// 会员购买底部弹窗
class _VipPurchaseSheet extends StatefulWidget {
  final VoidCallback onActivated;
  const _VipPurchaseSheet({required this.onActivated});

  @override
  State&lt;_VipPurchaseSheet&gt; createState() =&gt; _VipPurchaseSheetState();
}'''
new2 = '''// 会员购买底部弹窗
class _VipPurchaseSheet extends StatefulWidget {
  const _VipPurchaseSheet();

  @override
  State&lt;_VipPurchaseSheet&gt; createState() =&gt; _VipPurchaseSheetState();
}'''
content = content.replace(old2, new2)

# 3. 修改 _VipPurchaseSheetState 类，添加我们的代码
old3 = '''class _VipPurchaseSheetState extends State&lt;_VipPurchaseSheet&gt; {
  VipType _selectedType = VipType.monthly;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {'''
new3 = '''class _VipPurchaseSheetState extends State&lt;_VipPurchaseSheet&gt; {
  VipType _selectedType = VipType.monthly;
  bool _isLoading = false;
  bool _wasVipBeforePurchase = false;
  DateTime? _oldExpireDate;

  @override
  void initState() {
    super.initState();
    final vipService = getIt&lt;VipService&gt;();
    _wasVipBeforePurchase = vipService.isVip;
    _oldExpireDate = vipService.expireDate;
    // 监听 VIP 状态变化
    vipService.addListener(_onVipStatusChanged);
  }

  @override
  void dispose() {
    final vipService = getIt&lt;VipService&gt;();
    vipService.removeListener(_onVipStatusChanged);
    super.dispose();
  }

  void _onVipStatusChanged() {
    final vipService = getIt&lt;VipService&gt;();
    final newExpireDate = vipService.expireDate;
    
    // 情况1：新开通（之前不是 VIP，现在是 VIP）
    if (!_wasVipBeforePurchase &amp;&amp; vipService.isVip) {
      if (mounted) {
        setState(() =&gt; _isLoading = false);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('会员开通成功！感谢您的支持 🎉')),
        );
        // 刷新当前页
        context.go('/settings');
      }
    }
    
    // 情况2：续费（之前已经是 VIP，现在到期时间延长了）
    else if (_wasVipBeforePurchase &amp;&amp; vipService.isVip &amp;&amp; _isLoading) {
      // 只有到期时间真的延长了才算续费成功
      if (_oldExpireDate != null &amp;&amp; newExpireDate != null &amp;&amp; newExpireDate.isAfter(_oldExpireDate!)) {
        if (mounted) {
          setState(() =&gt; _isLoading = false);
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('续费成功！')),
          );
          context.go('/settings');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {'''
content = content.replace(old3, new3)

# 4. 修改 build 方法中的购买逻辑，移除 success 变量和 if (success) widget.onActivated()
old4 = '''              onPressed: _isLoading ? null : () async {
                setState(() =&gt; _isLoading = true);
                try {
                  bool success;
                  if (_selectedType == VipType.monthly) {
                    success = await vipService.purchaseMonthly();
                  } else {
                    success = await vipService.purchaseYearly();
                  }
                  if (success) widget.onActivated();
                } catch (e) {
                  setState(() =&gt; _isLoading = false);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('开通失败: $e')),
                    );
                  }
                }
              },'''
new4 = '''              onPressed: _isLoading ? null : () async {
                setState(() =&gt; _isLoading = true);
                try {
                  if (_selectedType == VipType.monthly) {
                    await vipService.purchaseMonthly();
                  } else {
                    await vipService.purchaseYearly();
                  }
                } catch (e) {
                  if (mounted) {
                    setState(() =&gt; _isLoading = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('开通失败: $e')),
                    );
                  }
                }
                // 安全网：30秒后强制重置 loading 状态，避免一直转圈
                Future.delayed(const Duration(seconds: 30), () {
                  if (mounted) setState(() =&gt; _isLoading = false);
                });
              },'''
content = content.replace(old4, new4)

# 5. 修改「恢复购买」按钮，移除 widget.onActivated()
old5 = '''              onPressed: () async {
                Navigator.pop(context);
                await vipService.restorePurchases();
                widget.onActivated();
              },'''
new5 = '''              onPressed: () async {
                Navigator.pop(context);
                await vipService.restorePurchases();
              },'''
content = content.replace(old5, new5)

# 写回文件
with open('/Users/phil/.openclaw/workspace-feishu/agent-forge/ai_accountant/lib/features/accounting/presentation/pages/settings_page.dart', 'w') as f:
    f.write(content)

print("Done!")
