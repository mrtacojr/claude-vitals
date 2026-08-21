#!/usr/bin/env bash
# Hook de estado para claude-vitals.
# Claude Code lo invoca en eventos del ciclo de vida (UserPromptSubmit, Stop,
# Notification, etc.) pasando un JSON por stdin. Registra el estado de la
# sesión, pinta las señales visuales de la ventana y manda una notificación de
# macOS si Claude se queda esperando.
#
# Estados: working (verde), idle (amarillo), waiting (rojo, esperando al usuario)
#
# Archivo de estado, ~/.claude/vitals-state/<session_id>, 4 líneas:
#   1: estado · 2: cwd del proyecto · 3: identidad de la ventana · 4: PID de claude
# Las líneas 3 y 4 son las que permiten `vitals go` y descartar sesiones muertas.
# La línea 3 es el pane_id de herdr (w2:p3) cuando la sesión vive en un panel, y
# el UUID de iTerm2 cuando no: se distinguen por el ':' que solo el pane_id lleva.

input=$(cat)

configDir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# ---- Config: vitals.conf > variables de entorno > defaults ----
# shellcheck source=/dev/null
[ -f "$configDir/vitals.conf" ] && . "$configDir/vitals.conf"
: "${VITALS_TAB_COLOR:=1}"
: "${VITALS_NOTIFY:=1}"
: "${VITALS_NOTIFY_DELAY:=10}"
: "${VITALS_WINDOW_BG:=1}"
: "${VITALS_BG_WAITING:=4a1015}"
: "${VITALS_BG_WORKING:=0f2a18}"
: "${VITALS_BG_IDLE:=2e2408}"
: "${VITALS_BADGE:=1}"
: "${VITALS_BADGE_TEXT:=ESPERA}"
: "${VITALS_ATTENTION:=once}"
: "${VITALS_STALE_HOURS:=12}"

# Librería compartida (resolviendo el symlink de instalación)
self="$0"; [ -L "$self" ] && self="$(readlink "$self")"
libfile="$(cd "$(dirname "$self")" && pwd)/vitals-lib.sh"
# shellcheck source=/dev/null
[ -f "$libfile" ] && . "$libfile"

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
proj=$(basename "${cwd:-sesión}")

set_state() {
  printf '%s\n%s\n%s\n%s\n' \
    "$1" "$cwd" "$(vitals_session_target)" "$(vitals_claude_pid)" >"$state_dir/$session"
  vitals_herdr_sidecar_write "$state_dir/$session.herdr"
}

# Secuencias propietarias de iTerm2 para el color del tab; otras terminales las
# ignoran. Van por vitals_tty, que resuelve el terminal real de la sesión: los
# hooks corren sin terminal controlador, así que escribir a /dev/tty no llegaba.
tab_color() { # r g b
  [ "$VITALS_TAB_COLOR" = 1 ] || return 0
  type vitals_tty >/dev/null 2>&1 || return 0
  vitals_in_herdr && return 0   # el tab es de la ventana de herdr, no de la sesión
  vitals_tty '\033]6;1;bg;red;brightness;%d\a\033]6;1;bg;green;brightness;%d\a\033]6;1;bg;blue;brightness;%d\a' "$1" "$2" "$3"
}
tab_reset() {
  [ "$VITALS_TAB_COLOR" = 1 ] || return 0
  type vitals_tty >/dev/null 2>&1 || return 0
  vitals_in_herdr && return 0
  vitals_tty '\033]6;1;bg;*;default\a'
}

# ---- Señales visuales de la ventana -----------------------------------------
# El fondo sigue los tres estados; el badge solo se pone en waiting, que es el
# único donde importa saber de qué proyecto se trata sin entrar a la ventana.
# Los marcadores .bg y .badge guardan lo ya aplicado para no reescribir al
# terminal en cada evento —PostToolUse se dispara muy seguido— y para que una
# escritura fallida se reintente en vez de darse por buena.
signals_sync() { # $1 = estado
  type vitals_bg_sync >/dev/null 2>&1 || return 0
  [ "$VITALS_WINDOW_BG" = 1 ] && vitals_bg_sync "$1" "$state_dir/$session.bg"
  if [ "$VITALS_BADGE" = 1 ]; then
    if [ "$1" = waiting ]; then
      if [ ! -f "$state_dir/$session.badge" ]; then
        vitals_badge_set "$VITALS_BADGE_TEXT
$proj" && : >"$state_dir/$session.badge"
      fi
    elif [ -f "$state_dir/$session.badge" ]; then
      vitals_badge_clear && rm -f "$state_dir/$session.badge"
    fi
  fi
  return 0
}

signals_clear() { # devuelve la ventana a su color de perfil y quita el badge
  type vitals_bg_reset >/dev/null 2>&1 || return 0
  [ "$VITALS_WINDOW_BG" = 1 ] && vitals_bg_reset
  [ "$VITALS_BADGE" = 1 ] && vitals_badge_clear
  rm -f "$state_dir/$session.bg" "$state_dir/$session.badge"
  return 0
}

case "$event" in
  UserPromptSubmit|PostToolUse)
    set_state working
    tab_color 0 190 70
    signals_sync working
    ;;
  SessionStart)
    set_state idle
    tab_color 235 180 0
    # Los marcadores de la sesión anterior de esta ventana se fueron con ella,
    # así que aquí no se sabe qué color quedó puesto: se limpia a ciegas y se
    # vuelve a aplicar. Es lo que rescata una ventana que quedó pintada porque
    # su sesión murió sin disparar SessionEnd.
    signals_clear
    signals_sync idle
    ;;
  Stop)
    set_state idle
    tab_color 235 180 0
    signals_sync idle
    ;;
  Notification)
    set_state waiting
    tab_color 230 40 40
    signals_sync waiting
    # Notificación de macOS, solo si tras VITALS_NOTIFY_DELAY segundos la sesión
    # sigue esperando (evita ruido cuando respondes de inmediato).
    if [ "$VITALS_NOTIFY" = 1 ] && command -v osascript >/dev/null 2>&1; then
      body="${msg:-Claude espera tu respuesta}"
      # sin comillas dobles ni backslashes en lo que se interpola a AppleScript
      nproj=${proj//[\"\\]/}; body=${body//[\"\\]/}
      (
        sleep "$VITALS_NOTIFY_DELAY"
        [ "$(head -n 1 "$state_dir/$session" 2>/dev/null)" = waiting ] || exit 0
        osascript -e "display notification \"$body\" with title \"🔴 $nproj\" subtitle \"claude-vitals\" sound name \"Ping\"" >/dev/null 2>&1
      ) &
    fi
    ;;
  SessionEnd)
    signals_clear
    rm -f "$state_dir/$session" "$state_dir/$session.git" "$state_dir/$session.audit" \
          "$state_dir/$session.herdr"
    tab_reset
    ;;
esac

# ---- Recolección de basura ---------------------------------------------------
# Antes se borraba por antigüedad del archivo de estado, cuyo mtime solo avanza
# con los eventos del hook: una sesión abierta pero inactiva perdía su estado
# mientras seguía viva, y sus caches quedaban huérfanos para siempre. Ahora la
# vida de una sesión la define el PID de su proceso claude.
if type vitals_is_session_file >/dev/null 2>&1; then
  now=$(date +%s)
  for f in "$state_dir"/*; do
    [ -f "$f" ] || continue
    vitals_is_session_file "$f" || continue
    pid=$(sed -n 4p "$f")
    dead=0
    if [ -n "$pid" ]; then
      kill -0 "$pid" 2>/dev/null || dead=1
    else
      # Escrito por una versión anterior: sin PID, se descarta por antigüedad.
      mt=$(stat -f %m "$f" 2>/dev/null || echo "$now")
      [ $((now - mt)) -gt $((VITALS_STALE_HOURS * 3600)) ] && dead=1
    fi
    [ "$dead" = 1 ] && rm -f "$f" "$f.git" "$f.audit" "$f.bg" "$f.badge" "$f.herdr"
  done
  # Caches cuya sesión ya no existe (huérfanos de versiones anteriores)
  for c in "$state_dir"/*.git "$state_dir"/*.audit "$state_dir"/*.bg "$state_dir"/*.badge \
           "$state_dir"/*.herdr; do
    [ -e "$c" ] || continue
    [ -f "${c%.*}" ] || rm -f "$c"
  done
fi

exit 0
