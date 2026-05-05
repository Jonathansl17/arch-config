#!/bin/bash
# Copy-mode: cualquier tecla → cancel + reenvía la tecla al pane.

printable=(
  {a..z} {A..Z} {0..9}
  '`' '~' '!' '@' '#' '$' '%' '^' '&' '*' '(' ')'
  '-' '_' '=' '+' '[' ']' '{' '}' ';' ':' "'" '"'
  ',' '.' '/' '?' '\' '|' '<' '>'
  ' '
)

named=(
  Enter Tab BSpace
  Up Down Left Right Home End PPage NPage IC DC
  F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12
)

for k in "${printable[@]}"; do
  tmux bind -T copy-mode "$k" "send -X cancel ; send-keys -l -- \"$k\"" 2>/dev/null
done

for k in "${named[@]}"; do
  tmux bind -T copy-mode "$k" "send -X cancel ; send-keys $k" 2>/dev/null
done

# Espacio explícito (named) — además del literal
tmux bind -T copy-mode Space "send -X cancel ; send-keys Space" 2>/dev/null

# Ctrl + letra/dígito → cancel + reenviar
for c in {a..z} {0..9}; do
  tmux bind -T copy-mode "C-$c" "send -X cancel ; send-keys C-$c" 2>/dev/null
done

# Alt + letra
for c in {a..z}; do
  tmux bind -T copy-mode "M-$c" "send -X cancel ; send-keys M-$c" 2>/dev/null
done

# Escape: cancela y reenvía (preserva secuencias bracketed-paste \e[200~)
tmux bind -T copy-mode Escape "send -X cancel ; send-keys Escape"
# q: solo cancela
tmux bind -T copy-mode q send -X cancel
