#!/usr/bin/python3
# -*- coding: utf-8 -*-

import sys, os
from PyQt5.QtGui import QGuiApplication, QClipboard
from PyQt5.QtCore import QMimeData

# If a path is provided, copy it; otherwise copy the current working directory.
path = sys.argv[1] if len(sys.argv) >= 2 else os.getcwd()

# Strip trailing whitespace/newlines so pasting into a shell
# does not auto-execute the command.
path = path.rstrip()

app = QGuiApplication([])
cb: QClipboard = QGuiApplication.clipboard()

mime = QMimeData()
mime.setText(path)

cb.setMimeData(mime, mode=QClipboard.Clipboard)

app.exec_()
