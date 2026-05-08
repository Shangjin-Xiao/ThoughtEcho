with open("lib/widgets/enhanced_markdown_widgets.dart", "r", encoding="utf-8") as f:
    content = f.read()

import re

new_content = content.replace("tooltip: _isCopied ? '已复制' : '复制代码',", "tooltip: _isCopied ? AppLocalizations.of(context).copiedCode : AppLocalizations.of(context).copyCode,")

with open("lib/widgets/enhanced_markdown_widgets.dart", "w", encoding="utf-8") as f:
    f.write(new_content)
print("Updated dart file.")
