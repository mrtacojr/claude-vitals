#!/usr/bin/env bash
# Hook de estado para claude-vitals.
# Claude Code lo invoca en eventos del ciclo de vida (UserPromptSubmit, Stop,
# Notification, etc.) pasando un JSON por stdin. Registra el estado de la
# sesión en un archivo (que vitals.sh lee para el semáforo) y pinta el color
# del tab de iTerm2 para que se vea de lejos.
#
# Estados: working (verde), idle (amarillo), waiting (rojo, esperando al usuario)

input=$(cat)
event=$(echo "$input" | jq -r '.hook_event_name // empty')
session=$(echo "$input" | jq -r '.session_id // empty')

[ -n "$event" ] && [ -n "$session" ] || exit 0

state_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/vitals-state"
mkdir -p "$state_dir"

# Secuencias propietarias de iTerm2 para el color del tab; otras terminales las ignoran
tab_color() { # r g b
  { printf '\033]6;1;bg;red;brightness;%d\a\033]6;1;bg;green;brightness;%d\a\033]6;1;bg;blue;brightness;%d\a' "$1" "$2" "$3" >/dev/tty; } 2>/dev/null || true
}
tab_reset() {
  { printf '\033]6;1;bg;*;default\a' >/dev/tty; } 2>/dev/null || true
}

case "$event" in
  UserPromptSubmit|PostToolUse)
    echo working >"$state_dir/$session"
    tab_color 0 190 70
    ;;
  Stop|SessionStart)
    echo idle >"$state_dir/$session"
    tab_color 235 180 0
    ;;
  Notification)
    echo waiting >"$state_dir/$session"
    tab_color 230 40 40
    ;;
  SessionEnd)
    rm -f "$state_dir/$session"
    tab_reset
    ;;
esac

# Limpieza de archivos de sesiones viejas
find "$state_dir" -type f -mtime +2 -delete 2>/dev/null

exit 0
