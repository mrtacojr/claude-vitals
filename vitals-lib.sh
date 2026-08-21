# shellcheck shell=bash
# vitals-lib.sh — funciones compartidas entre vitals.sh (statusline),
# vitals-hook.sh y vitals (CLI). Se carga con `source`; no ejecutar directamente.

# ===========================================================================
# tri-audit
# ===========================================================================

# Badge de tri-audit (metodología de contrapeso 3-IA).
# Lee la tabla de fases de <proyecto>/.audit/estado.md — la fuente de verdad que
# la propia skill mantiene con tokens exactos (completada/PASS/REWORK/STOP).
# Imprime una de: "STOP F<n>" | "F<n> gate" | "F<n>↺" | "F<n>" | "OK" | nada.
vitals_audit_badge() { # $1 = directorio del proyecto
  local f="$1/.audit/estado.md"
  [ -f "$f" ] || return 0
  awk -F'|' '
    /^\| *[0-9]+ *\|/ {
      gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $4); gsub(/^ +| +$/, "", $5)
      total++
      if ($5 ~ /STOP/) stop = 1
      if ($5 ~ /REWORK/) rw = 1
      # misma regla de auto-detección de la skill: pendiente si Estado no es
      # "completada" o Veredicto no es PASS
      if (first == "" && !($4 ~ /^completada/ && $5 ~ /PASS/)) first = $2
    }
    END {
      if (total == 0) exit
      if (stop)          { print "STOP F" first; exit }
      if (first == "")   { print "OK"; exit }
      out = "F" first
      if (rw) out = out "↺"
      if (first == 7) out = out " gate"   # el ciclo se pausa antes del deploy
      print out
    }' "$f"
}

# ===========================================================================
# Modo herdr
# ===========================================================================
# Dentro de un panel de herdr, TERM_PROGRAM y LC_TERMINAL siguen diciendo
# "iTerm2" porque el panel los hereda del cliente herdr, pero quien interpreta
# lo que escribimos al terminal es el emulador de herdr, no iTerm2. Y la ventana
# dejó de ser de la sesión: decenas de paneles comparten una sola. Por eso bajo
# herdr se apagan todas las señales de ventana, y la identidad de la sesión deja
# de ser el UUID de iTerm2 —idéntico en todos los paneles, porque lo hereda del
# cliente— para pasar a ser el pane_id, que sí distingue un panel de otro.
vitals_in_herdr() { [ "${HERDR_ENV:-}" = 1 ]; }

# La única pregunta válida antes de emitir una secuencia propietaria de iTerm2
# no es "qué dice TERM_PROGRAM" sino "quién va a leer esto".
vitals_is_iterm2() {
  vitals_in_herdr && return 1
  [ "${TERM_PROGRAM:-}" = iTerm.app ]
}

# Nombre AppleScript de la app dueña de la ventana donde vive herdr.
# TERM_PROGRAM miente sobre quién lee las secuencias de escape dentro del panel,
# pero acierta sobre de quién es la ventana: es justo lo que el panel hereda del
# cliente herdr. Devuelve 1 si no reconoce la app, para que el llamador no
# invente un `tell application` que no existe.
vitals_term_app() { # $1 = valor de TERM_PROGRAM
  case "$1" in
    iTerm.app)      printf 'iTerm2' ;;
    Apple_Terminal) printf 'Terminal' ;;
    ghostty)        printf 'Ghostty' ;;
    WezTerm)        printf 'WezTerm' ;;
    Alacritty)      printf 'Alacritty' ;;
    kitty)          printf 'kitty' ;;
    *)              return 1 ;;
  esac
}

# ===========================================================================
# Señales visuales de la ventana
# ===========================================================================
# Todo va a /dev/tty, nunca a stdout: la statusline manda su texto por stdout y
# el hook no debe ensuciar la salida. Si no hay tty controlador, no pasa nada.

# Dispositivo tty de la ventana donde vive esta sesión.
# NO se puede usar /dev/tty: los subprocesos que lanza Claude Code —statusline y
# hooks— corren sin terminal controlador, así que /dev/tty falla con "device not
# configured" y las secuencias no llegan a ninguna parte. El terminal real se
# resuelve por el PID del proceso claude, que sí lo tiene.
vitals_session_tty() { # $1 = pid de claude (por defecto, el de esta sesión)
  local pid="${1:-$(vitals_claude_pid)}" t
  [ -n "$pid" ] || return 1
  t=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
  case "$t" in
    "" | "??" | "-") return 1 ;;
    /dev/*)          printf '%s' "$t" ;;
    *)               printf '/dev/%s' "$t" ;;
  esac
}

# Devuelve el estado real de la escritura: si el terminal no es escribible, esto
# falla y el llamador no debe dar la señal por aplicada. Un marcador optimista
# haría que el sistema creyera pintada una ventana que quedó gris.
vitals_tty() { # $1 = formato de printf, resto = argumentos
  if [ -z "${_vitals_tty_dev:-}" ]; then
    _vitals_tty_dev=$(vitals_session_tty) || _vitals_tty_dev=/dev/tty
  fi
  # shellcheck disable=SC2059  # el formato ES $1 a propósito: todos los
  # llamadores de abajo lo pasan como literal, nunca con datos interpolados.
  printf "$@" >"$_vitals_tty_dev" 2>/dev/null
}

# Fondo de la ventana completa: la señal con más superficie visible cuando
# tienes decenas de ventanas y las miras desde Mission Control.
# En iTerm2 se usa la secuencia propietaria; en el resto, OSC 11/111, que es
# el estándar que entienden kitty, WezTerm, Ghostty y xterm.
vitals_bg_set() { # $1 = color hex sin '#'
  # Bajo herdr no hay ventana de esta sesión que pintar: se devuelve fallo, no
  # un éxito falso, para que nadie apunte "ya está pintada".
  vitals_in_herdr && return 1
  if vitals_is_iterm2; then vitals_tty '\033]1337;SetColors=bg=%s\a' "$1"
  else                      vitals_tty '\033]11;#%s\a' "$1"
  fi
}

vitals_bg_reset() {
  # Se emiten las dos: 'SetColors=bg=default' es la de iTerm2 y OSC 111 la
  # estándar. No basta con la primera —hay builds de iTerm2 que aceptan la
  # secuencia sin honrar el valor 'default', y entonces la escritura "tiene
  # éxito" pero la ventana se queda pintada—, así que se manda también la
  # estándar. Restaurar con un hex fijo no es opción: el perfil puede tener
  # colores distintos para modo claro y oscuro.
  vitals_in_herdr && return 1
  if vitals_is_iterm2; then vitals_tty '\033]1337;SetColors=bg=default\a\033]111\a'
  else                      vitals_tty '\033]111\a'
  fi
}

# Sincroniza el fondo de la ventana con el estado de la sesión.
# El marcador guarda el color aplicado, no un simple "pintada sí/no": así se
# compara contra el que toca y solo se escribe al terminal cuando cambian de
# verdad. Sin eso habría una escritura por refresco de statusline y otra por
# cada PostToolUse.
# Un color vacío o "-" significa "no pintar ese estado", para poder desactivar
# estados sueltos desde vitals.conf.
vitals_bg_sync() { # $1 = estado  $2 = ruta del marcador
  local st="$1" marker="$2" want have
  # Bajo herdr no hay ventana por sesión: nada que sincronizar. Se borra el
  # marcador que pudiera haber dejado una versión anterior para que no quede
  # afirmando un color aplicado que ya nadie mantiene.
  if vitals_in_herdr; then rm -f "$marker"; return 0; fi
  case "$st" in
    waiting) want="${VITALS_BG_WAITING-}" ;;
    working) want="${VITALS_BG_WORKING-}" ;;
    *)       want="${VITALS_BG_IDLE-}" ;;
  esac
  [ "$want" = "-" ] && want=""
  have=""
  [ -f "$marker" ] && read -r have <"$marker"
  [ "$want" = "$have" ] && return 0
  if [ -z "$want" ]; then
    vitals_bg_reset || return 1
    rm -f "$marker"
  else
    vitals_bg_set "$want" || return 1
    printf '%s\n' "$want" >"$marker"
  fi
}

# Badge de iTerm2: texto translúcido grande en la esquina superior derecha.
# Se auto-escala hasta el 50% del ancho y 20% del alto de la sesión, así que
# textos cortos se ven enormes; por eso el formato es "ESTADO\nproyecto".
vitals_badge_set() { # $1 = texto (puede llevar saltos de línea)
  vitals_is_iterm2 || return 1
  vitals_tty '\033]1337;SetBadgeFormat=%s\a' "$(printf '%s' "$1" | base64 | tr -d '\n')"
}

vitals_badge_clear() {
  vitals_is_iterm2 || return 1
  vitals_tty '\033]1337;SetBadgeFormat=\a'
}

# Rebote del ícono de iTerm2 en el Dock: se ve desde cualquier Space sin abrir
# Mission Control. once = un rebote · yes = hasta que actives iTerm2 ·
# fireworks = animación sobre la sesión.
vitals_attention() { # $1 = once|yes|fireworks
  vitals_is_iterm2 || return 1
  vitals_tty '\033]1337;RequestAttention=%s\a' "$1"
}

# ===========================================================================
# Sesiones: identidad y liveness
# ===========================================================================

# UUID de la sesión de iTerm2 (ITERM_SESSION_ID viene como "w12t0p0:UUID").
# Solo se guarda el UUID: el prefijo de ventana/tab se queda obsoleto si mueves
# la pestaña, el UUID no.
vitals_iterm_uuid() {
  [ -n "${ITERM_SESSION_ID:-}" ] || return 0
  printf '%s' "${ITERM_SESSION_ID##*:}"
}

# Identidad de la sesión para `vitals go`: bajo herdr el pane_id, fuera el UUID
# de iTerm2. Es lo que va en la línea 3 del archivo de estado; el formato de 4
# líneas no cambia, cambia lo que significa esa línea.
# Si HERDR_ENV=1 pero no llega HERDR_PANE_ID, se cae al UUID: es preferible una
# identidad heredada y ambigua a una vacía, que dejaría la sesión inalcanzable.
vitals_session_target() {
  if vitals_in_herdr && [ -n "${HERDR_PANE_ID:-}" ]; then
    printf '%s' "$HERDR_PANE_ID"
  else
    vitals_iterm_uuid
  fi
}

# Se discrimina por FORMATO, no por el modo del proceso que lee: un pane_id de
# herdr lleva ':' (w2:p3) y un UUID de iTerm2 nunca. Así conviven en el mismo
# directorio los archivos de sesiones dentro y fuera de herdr, y los que dejó
# una versión anterior.
vitals_target_is_pane() { # $1 = contenido de la línea 3
  case "$1" in *:*) return 0 ;; *) return 1 ;; esac
}

# `vitals go` también lo dispara SwiftBar, que lanza el plugin SIN el entorno
# del panel: sin HERDR_SOCKET_PATH el cliente busca el socket por defecto, no lo
# encuentra y falla con server_not_running (medido). Por eso cada sesión bajo
# herdr deja al lado de su estado el socket de su servidor, la app dueña de la
# ventana y la ruta del binario —SwiftBar tampoco hereda el PATH que tiene a
# herdr (comprobado: no está en /usr/bin:/bin:/usr/sbin:/sbin)—. Va en un
# archivo aparte a propósito: el estado sigue siendo de 4 líneas exactas.
vitals_herdr_sidecar_write() { # $1 = ruta del sidecar
  vitals_in_herdr || return 0
  [ -n "${HERDR_SOCKET_PATH:-}" ] || return 0
  printf '%s\n%s\n%s\n' \
    "$HERDR_SOCKET_PATH" "${TERM_PROGRAM:-}" "${HERDR_BIN_PATH:-}" >"$1"
}

# PID del proceso `claude` que corre esta sesión, subiendo por el árbol desde
# el hook (hook -> shell -> claude). Es lo que permite distinguir una sesión
# viva de una cuya terminal cerraste sin que disparara SessionEnd.
vitals_claude_pid() {
  local p="${1:-$PPID}" i=0
  while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && [ $i -lt 6 ]; do
    case "$(ps -o comm= -p "$p" 2>/dev/null)" in
      *claude) printf '%s' "$p"; return 0 ;;
    esac
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    i=$((i + 1))
  done
  return 1
}

# 0 = viva · 1 = muerta · 2 = desconocida (archivo escrito por una versión
# anterior, sin PID registrado)
vitals_alive() { # $1 = pid
  [ -n "$1" ] || return 2
  kill -0 "$1" 2>/dev/null
}

# ¿El basename es un archivo de sesión y no un cache (.git/.audit/.signal) ni
# un archivo global (ai-health, ai-refresh.lock)?
vitals_is_session_file() { # $1 = ruta
  local b; b=$(basename "$1")
  case "$b" in
    *.*)       return 1 ;;   # cualquier cache o lock lleva punto
    ai-health) return 1 ;;   # cache global del badge 3IA, no es una sesión
    *)         return 0 ;;
  esac
}
