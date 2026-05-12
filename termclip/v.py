#!/usr/bin/python3
# -*- coding: utf-8 -*-

import os, sys, shutil
from urllib.parse import urlparse, unquote
from PyQt5.QtGui import QGuiApplication, QClipboard

def from_file_uri(uri: str) -> str:
    """Comverts file:// URI in a local route."""
    return unquote(urlparse(uri).path)

def get_unique_name(dest_dir: str, filename: str) -> str:
    """
    Generates an unique name in the folder if the file already exists
    """
    name, ext = os.path.splitext(filename)
    candidate = filename
    counter = 1

    while os.path.exists(os.path.join(dest_dir, candidate)):
        if counter == 1:
            candidate = f"{name}_copy{ext}"
        else:
            candidate = f"{name}_copy{counter}{ext}"
        counter += 1

    return candidate

# Init Qt
app = QGuiApplication([])
cb: QClipboard = QGuiApplication.clipboard()
mime = cb.mimeData()

# Check clipboard content
if not mime.hasFormat("x-special/gnome-copied-files"):
    sys.exit(1)

# Parse clipboard content
data = mime.data("x-special/gnome-copied-files").data().decode("utf-8").strip().split("\n")

# Get operation and files
operation = data[0].strip().lower()
files = [from_file_uri(uri) for uri in data[1:] if uri.startswith("file://")]

# Paste files to current directory
dest = os.getcwd()
pasted = []

for f in files:
    try:
        #Gets the unique name if already exists
        unique_name = get_unique_name(dest, os.path.basename(f))
        target = os.path.join(dest, unique_name)

        if operation == "copy":
            if os.path.isdir(f):
                shutil.copytree(f, target, dirs_exist_ok=True)
            else:
                shutil.copy2(f, target)
        elif operation == "cut":
            shutil.move(f, target)

        pasted.append(unique_name)
    except Exception as e:
        print(f"Error al pegar {f}: {e}", file=sys.stderr)
        pass

#Return pasted files or exit with error
if pasted:
    print("\n".join(pasted))
    sys.exit(0)
else:
    sys.exit(1)
