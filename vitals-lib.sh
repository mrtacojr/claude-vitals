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
  case "${TERM_PROGRAM:-}" in
    iTerm.app) vitals_tty '\033]1337;SetColors=bg=%s\a' "$1" ;;
    *)         vitals_tty '\033]11;#%s\a' "$1" ;;
  esac
}

vitals_bg_reset() {
  # 'default' devuelve el color del perfil respetando los colores separados de
  # modo claro/oscuro. Restaurar con un hex fijo se rompería al cambiar de
  # apariencia, por eso nunca se hardcodea el color original.
  case "${TERM_PROGRAM:-}" in
    iTerm.app) vitals_tty '\033]1337;SetColors=bg=default\a' ;;
    *)         vitals_tty '\033]111\a' ;;
  esac
}

# Badge de iTerm2: texto translúcido grande en la esquina superior derecha.
# Se auto-escala hasta el 50% del ancho y 20% del alto de la sesión, así que
# textos cortos se ven enormes; por eso el formato es "ESTADO\nproyecto".
vitals_badge_set() { # $1 = texto (puede llevar saltos de línea)
  [ "${TERM_PROGRAM:-}" = iTerm.app ] || return 1
  vitals_tty '\033]1337;SetBadgeFormat=%s\a' "$(printf '%s' "$1" | base64 | tr -d '\n')"
}

vitals_badge_clear() {
  [ "${TERM_PROGRAM:-}" = iTerm.app ] || return 1
  vitals_tty '\033]1337;SetBadgeFormat=\a'
}

# Rebote del ícono de iTerm2 en el Dock: se ve desde cualquier Space sin abrir
# Mission Control. once = un rebote · yes = hasta que actives iTerm2 ·
# fireworks = animación sobre la sesión.
vitals_attention() { # $1 = once|yes|fireworks
  [ "${TERM_PROGRAM:-}" = iTerm.app ] || return 1
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
