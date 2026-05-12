#!/usr/bin/python3
# -*- coding: utf-8 -*-

import sys, os, pathlib
from urllib.parse import quote
from PyQt5.QtGui import QGuiApplication, QClipboard, QImage
from PyQt5.QtCore import QMimeData, QBuffer, QByteArray, QIODevice

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".bmp", ".gif", ".webp", ".tiff", ".tif", ".ppm", ".xbm", ".xpm"}

def to_file_uri(path: str) -> str:
    p = str(pathlib.Path(path).expanduser().resolve())
    return "file://" + quote(p)

# Check args
if len(sys.argv) < 2:
    sys.exit(1)

paths = sys.argv[1:]
uris = []

# Validate files/folders
for path in paths:
    if not os.path.exists(path):
        sys.exit(1)
    uris.append(to_file_uri(path))

# Build payloads
payload_gcf = ("copy\n" + "\n".join(uris) + "\n").encode("utf-8")
payload_uris = ("\r\n".join(uris) + "\r\n").encode("utf-8")

# Init Qt
app = QGuiApplication([])
cb: QClipboard = QGuiApplication.clipboard()

mime = QMimeData()
mime.setData("x-special/gnome-copied-files", payload_gcf)
mime.setData("text/uri-list", payload_uris)
mime.setText("\n".join(uris))

# If a single image file was passed, also expose raster bytes so apps
# expecting inline images (chats, image editors, browsers) can paste it.
if len(paths) == 1:
    ext = pathlib.Path(paths[0]).suffix.lower()
    if ext in IMAGE_EXTS:
        img = QImage(paths[0])
        if not img.isNull():
            mime.setImageData(img)
            buf = QBuffer()
            buf.open(QIODevice.WriteOnly)
            img.save(buf, "PNG")
            mime.setData("image/png", QByteArray(buf.data()))

cb.setMimeData(mime, mode=QClipboard.Clipboard)

app.exec_()
