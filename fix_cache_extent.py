import os

def fix_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # The exact block to replace:
    #           scrollCacheExtent: ScrollCacheExtent.pixels(
    #             MediaQuery.sizeOf(context).height.clamp(400, 900).toDouble(),
    #           ),

    old_str1 = "scrollCacheExtent: ScrollCacheExtent.pixels("
    old_str2 = "MediaQuery.sizeOf(context).height.clamp(400, 900).toDouble(),"
    old_str3 = "          ),"

    lines = content.split('\n')
    new_lines = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if old_str1 in line:
            new_lines.append(line.replace(old_str1, "cacheExtent: " + old_str2))
            i += 2 # skip next two lines
        else:
            new_lines.append(line)
        i += 1

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write('\n'.join(new_lines))

def fix_integration_test(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    content = content.replace("scrollCacheExtent: const ScrollCacheExtent.pixels(800),", "cacheExtent: 800,")

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

fix_file('lib/widgets/note_list/note_list_items.dart')
fix_integration_test('integration_test/note_list_performance_test.dart')
