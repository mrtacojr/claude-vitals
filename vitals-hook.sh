#!/usr/bin/env bash
# Hook de estado para claude-vitals.
# Claude Code lo invoca en eventos del ciclo de vida (UserPromptSubmit, Stop,
# Notification, etc.) pasando un JSON por stdin. Registra el estado de la
# sesión (línea 1: estado, línea 2: cwd del proyecto), pinta el color del tab
# de iTerm2 y manda una notificación de macOS si Claude se queda esperando.
#
# Estados: working (verde), idle (amarillo), waiting (rojo, esperando al usuario)

input=$(cat)

configDir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# ---- Config: vitals.conf > variables de entorno > defaults ----
[ -f "$configDir/vitals.conf" ] && . "$configDir/vitals.conf"
: "${VITALS_TAB_COLOR:=1}"
: "${VITALS_NOTIFY:=1}"
: "${VITALS_NOTIFY_DELAY:=10}"

IFS=$'\t' read -r event session cwd msg <<EOF
$(echo "$input" | jq -r '[
  (.hook_event_name // ""),
  (.session_id // ""),
  (.cwd // ""),
  (.message // "")
] | @tsv')
EOF

[ -n "$event" ] && [ -n "$session" ] || exit 0

state_dir="$configDir/vitals-state"
mkdir -p "$state_dir"

set_state() {
  printf '%s\n%s\n' "$1" "$cwd" >"$state_dir/$session"
}

# Secuencias propietarias de iTerm2 para el color del tab; otras terminales las ignoran
tab_color() { # r g b
  [ "$VITALS_TAB_COLOR" = 1 ] || return 0
  { printf '\033]6;1;bg;red;brightness;%d\a\033]6;1;bg;green;brightness;%d\a\033]6;1;bg;blue;brightness;%d\a' "$1" "$2" "$3" >/dev/tty; } 2>/dev/null || true
}
tab_reset() {
  [ "$VITALS_TAB_COLOR" = 1 ] || return 0
  { printf '\033]6;1;bg;*;default\a' >/dev/tty; } 2>/dev/null || true
}

case "$event" in
  UserPromptSubmit|PostToolUse)
    set_state working
    tab_color 0 190 70
    ;;
  Stop|SessionStart)
    set_state idle
    tab_color 235 180 0
    ;;
  Notification)
    set_state waiting
    tab_color 230 40 40
    # Notificación de macOS, solo si tras VITALS_NOTIFY_DELAY segundos la sesión
    # sigue esperando (evita ruido cuando respondes de inmediato).
    if [ "$VITALS_NOTIFY" = 1 ] && command -v osascript >/dev/null 2>&1; then
      proj=$(basename "${cwd:-sesión}")
      body="${msg:-Claude espera tu respuesta}"
      # sin comillas dobles ni backslashes en lo que se interpola a AppleScript
      proj=${proj//[\"\\]/}; body=${body//[\"\\]/}
      (
        sleep "$VITALS_NOTIFY_DELAY"
        [ "$(head -n 1 "$state_dir/$session" 2>/dev/null)" = waiting ] || exit 0
        osascript -e "display notification \"$body\" with title \"🔴 $proj\" subtitle \"claude-vitals\" sound name \"Ping\"" >/dev/null 2>&1
      ) &
    fi
    ;;
  SessionEnd)
    rm -f "$state_dir/$session" "$state_dir/$session.git"
    tab_reset
    ;;
esac

# Limpieza de archivos de sesiones viejas
find "$state_dir" -type f -mtime +2 -delete 2>/dev/null

exit 0
