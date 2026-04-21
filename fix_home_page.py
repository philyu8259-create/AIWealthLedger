import re

with open('lib/features/accounting/presentation/pages/home_page.dart', 'r') as f:
    lines = f.readlines()

# 1. Remove the broken _showAiBottomSheet and _aiActionButton from inside the class
# We'll just look for '  void _showAiBottomSheet()' and delete lines until the end of _aiActionButton
start_idx = -1
end_idx = -1

for i, line in enumerate(lines):
    if line.startswith('  void _showAiBottomSheet() {'):
        start_idx = i
        break

if start_idx != -1:
    for i in range(start_idx, len(lines)):
        if lines[i].startswith('    final text = _textController.text.trim();'):
            end_idx = i
            break

if start_idx != -1 and end_idx != -1:
    del lines[start_idx:end_idx]

# Write back
with open('lib/features/accounting/presentation/pages/home_page.dart', 'w') as f:
    f.writelines(lines)
