#!/usr/bin/python3
# -*- coding: utf-8 -*-

import sys, os
from PyQt5.QtGui import QGuiApplication, QClipboard
from PyQt5.QtCore import QMimeData

# Check args
if len(sys.argv) < 2:
    print("Usage: cc <file>", file=sys.stderr)
    sys.exit(1)

path = sys.argv[1]

if not os.path.isfile(path):
    print(f"File not found: {path}", file=sys.stderr)
    sys.exit(1)

# Read file as UTF-8 text
try:
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
except UnicodeDecodeError:
    print(f"Cannot read '{path}' as text (binary file?)", file=sys.stderr)
    sys.exit(1)

# Strip trailing whitespace/newlines so pasting into a shell
# does not auto-execute the command.
content = content.rstrip()

# Init Qt
app = QGuiApplication([])
cb: QClipboard = QGuiApplication.clipboard()

mime = QMimeData()
mime.setText(content)

cb.setMimeData(mime, mode=QClipboard.Clipboard)

app.exec_()
