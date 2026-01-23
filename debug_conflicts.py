import re

file_path = 'lib/widgets/add_note_dialog.dart'

with open(file_path, 'r') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if line.startswith('<<<<<<<') or line.startswith('=======') or line.startswith('>>>>>>>'):
        print(f"Line {i+1}: {line.strip()}")
