import json
import re
import sys

def add_key_to_arb(filepath, key, value):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # We'll just insert it before the last closing brace
    # and hope the JSON remains valid.

    # Simple JSON parsing to ensure we can just add a key
    data = json.loads(content)
    if key in data:
        print(f"Key {key} already exists in {filepath}")
        return

    data[key] = value

    # Dump it back preserving the original format as much as possible is hard with json module
    # So we use regex to inject it

    match = re.search(r'}(\s*)$', content)
    if match:
        insertion = f',\n  "{key}": "{value}"'
        new_content = content[:match.start()] + insertion + content[match.start():]
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Added {key} to {filepath}")
    else:
        print(f"Failed to find end of JSON in {filepath}")

add_key_to_arb('lib/l10n/app_zh.arb', 'copyCode', '复制代码')
add_key_to_arb('lib/l10n/app_en.arb', 'copyCode', 'Copy code')
add_key_to_arb('lib/l10n/app_zh.arb', 'copiedCode', '已复制')
add_key_to_arb('lib/l10n/app_en.arb', 'copiedCode', 'Copied')
