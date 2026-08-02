# templates

User-content templates copied to `~/templates/`.

## Files

- `template.xopp` → `~/templates/template.xopp`

## Xournal++ default template

The `x` script in [`bin/x`](../bin/README.md) uses this template
(`bash/bashrc` aliases `xournalpp` to it):

- `x file.xopp` with non-existent path → copies template to
  that path, then opens it.
- `x file.xopp` with existing path → opens normally, doesn't
  touch the file.
- `x` with no args → opens xournalpp as usual.

Always launches detached (`setsid -f`), so the terminal stays free.

Lets you start new notebooks pre-formatted (page size, margins, ruling)
without going through xournalpp's new-file dialog.
