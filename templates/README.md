# templates

User-content templates copied to `~/templates/`.

## Files

- `template.xopp` → `~/templates/template.xopp`

## Xournal++ default template

The `xournalpp` shell function in `bash/bashrc` uses this template:

- `xournalpp file.xopp` with non-existent path → copies template to
  that path, then opens it.
- `xournalpp file.xopp` with existing path → opens normally, doesn't
  touch the file.
- `xournalpp` with no args → opens xournalpp as usual.

Lets you start new notebooks pre-formatted (page size, margins, ruling)
without going through xournalpp's new-file dialog.
