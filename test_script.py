import sys

def extract_function(filepath, func_name):
    with open(filepath, 'r') as f:
        content = f.read()

    start = content.find(f"Future<void> {func_name}() async {{")
    if start == -1:
        print("Function not found")
        return

    braces = 0
    in_string = False
    string_char = ''

    for i in range(start, len(content)):
        char = content[i]

        if in_string:
            if char == string_char and content[i-1] != '\\':
                in_string = False
            continue

        if char == '"' or char == "'":
            in_string = True
            string_char = char
            continue

        if char == '{':
            braces += 1
        elif char == '}':
            braces -= 1
            if braces == 0:
                print(content[start:i+1])
                return

extract_function('lib/services/settings_service.dart', '_secureLegacyApiKey')
