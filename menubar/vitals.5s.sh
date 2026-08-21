#!/usr/bin/env bash
# <bitbar.title>claude-vitals</bitbar.title>
# <bitbar.version>1.0</bitbar.version>
# <bitbar.author>claude-vitals</bitbar.author>
# <bitbar.desc>Sesiones de Claude Code en la barra de menú: cuántas te esperan y salto de un clic.</bitbar.desc>
# <bitbar.dependencies>bash,claude-vitals</bitbar.dependencies>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
#
# Ítem de barra de menú para claude-vitals: siempre visible, sin entrar a
# Mission Control. El título dice si algo te espera; el desplegable lista las
# sesiones y al hacer clic en una salta a su ventana.
#
# Instalación: enlázalo a la carpeta de plugins de SwiftBar, p.ej.
#   ln -sf "$(pwd)/menubar/vitals.5s.sh" ~/.swiftbar/vitals.5s.sh

self="$0"; [ -L "$self" ] && self="$(readlink "$self")"
VITALS="$(cd "$(dirname "$self")/.." && pwd)/vitals"

fmt_age() { # segundos -> "45s" / "12m" / "1h05m"
  local s=$1
  if [ "$s" -lt 60 ]; then printf '%ds' "$s"
  elif [ "$s" -lt 3600 ]; then printf '%dm' "$((s / 60))"
  else printf '%dh%02dm' "$((s / 3600))" "$(((s % 3600) / 60))"
  fi
}

# Se cambia el tabulador por 0x1F antes de leer: `read` con IFS=tab colapsa
# tabuladores seguidos, así que una sesión sin badge de auditoría (o sin
# identidad, escrita por una versión anterior) desplazaba las columnas y el
# renglón acababa apuntando a la sesión equivocada.
rows=$("$VITALS" --porcelain 2>/dev/null | tr '\t' '\037')

if [ -z "$rows" ]; then
  echo "◦"
  echo "---"
  echo "Sin sesiones de Claude Code activas"
  exit 0
fi

waiting=0 working=0 idle=0
while IFS=$'\037' read -r state _ _ _ _; do
  case "$state" in
    waiting) waiting=$((waiting + 1)) ;;
    working) working=$((working + 1)) ;;
    *)       idle=$((idle + 1)) ;;
  esac
done <<<"$rows"

# El título es lo único visible sin desplegar, así que solo lleva el dato que
# exige acción: cuántas sesiones te esperan. Sin ninguna, muestra las que
# trabajan, y si tampoco hay, un punto discreto.
if [ "$waiting" -gt 0 ]; then
  echo "🔴 $waiting | color=red"
elif [ "$working" -gt 0 ]; then
  echo "🟢 $working"
else
  echo "◦"
fi

echo "---"

# La 4ª columna es la identidad de la sesión: un pane_id de herdr (w2:p3) o un
# UUID de iTerm2. Aquí no se distingue a propósito —se devuelve tal cual a
# `vitals go`, que sabe llevar cada una por su puerta: `herdr agent focus` para
# un panel, AppleScript para una ventana—. Así el plugin sirve a la vez a las
# sesiones que viven dentro de herdr y a las que no.
while IFS=$'\037' read -r state proj secs uuid badge; do
  case "$state" in
    waiting) icon="🔴"; color="red" ;;
    working) icon="🟢"; color="" ;;
    *)       icon="🟡"; color="" ;;
  esac
  label="$icon $proj · $(fmt_age "$secs")"
  # mismo criterio que el CLI: "OK" es una iteración de tri-audit completa
  case "$badge" in
    "") : ;;
    OK) label="$label · ⚖ ✓" ;;
    *)  label="$label · ⚖ $badge" ;;
  esac
  # param2 va entrecomillado: un pane_id lleva ':' y SwiftBar corta el
  # argumento en el primer espacio si no se le pone comillas.
  line="$label | bash=\"$VITALS\" param1=go param2=\"$uuid\" terminal=false refresh=true"
  [ -n "$color" ] && line="$line color=$color"
  echo "$line"
done <<<"$rows"

echo "---"
echo "$working trabajando · $waiting esperándote · $idle detenidas | size=11 color=gray"
echo "Refrescar | refresh=true"
