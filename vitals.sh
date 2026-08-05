#!/usr/bin/env bash
# claude-vitals — statusline de Claude Code.
# Muestra: semáforo de actividad, modelo, contexto, costo de la sesión y rama git.
# Módulos configurables en ~/.claude/vitals.conf (ver vitals.conf.example).
# Also forwards data to spacecake if running inside a spacecake terminal.

input=$(cat)

configDir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# ---- Config: vitals.conf > variables de entorno > defaults ----
[ -f "$configDir/vitals.conf" ] && . "$configDir/vitals.conf"
: "${VITALS_SEMAFORO:=1}"
: "${VITALS_MODEL:=1}"
: "${VITALS_CTX:=1}"
: "${VITALS_CTX_ALERT:=80}"
: "${VITALS_COST:=1}"
: "${VITALS_GIT:=1}"
: "${VITALS_GIT_CACHE_SECS:=10}"
: "${VITALS_IDLE_TIME:=1}"
: "${VITALS_RC:=1}"

# ---- Forward to spacecake if applicable (preserves existing integration) ----
if [ -n "${SPACECAKE_TERMINAL}" ]; then
  socketPath="${configDir}/spacecake.sock"
  if [ -S "$socketPath" ]; then
    echo "$input" | curl -s -X POST -H "Content-Type: application/json" -d @- \
      --unix-socket "$socketPath" --max-time 2 \
      http://localhost/statusline >/dev/null 2>&1 &
  fi
fi

# ---- Extraer todos los campos en una sola pasada de jq ----
IFS=$'\t' read -r model used remaining session_id cost cwd <<EOF
$(echo "$input" | jq -r '[
  (.model.display_name // "Unknown model"),
  (.context_window.used_percentage // "-"),
  (.context_window.remaining_percentage // "-"),
  (.session_id // "-"),
  (.cost.total_cost_usd // "-"),
  (.workspace.current_dir // .cwd // "-")
] | @tsv')
EOF

now=$(date +%s)
state_dir="$configDir/vitals-state"

fmt_age() { # segundos -> "45s" / "12m" / "1h05m"
  local s=$1
  if [ "$s" -lt 60 ]; then printf '%ds' "$s"
  elif [ "$s" -lt 3600 ]; then printf '%dm' "$((s / 60))"
  else printf '%dh%02dm' "$((s / 3600))" "$(((s % 3600) / 60))"
  fi
}

parts=()

# ---- Semáforo: estado escrito por vitals-hook.sh ----
# working parpadea verde, waiting parpadea rojo (requiere statusLine.refreshInterval),
# idle queda amarillo fijo con el tiempo que lleva detenido.
if [ "$VITALS_SEMAFORO" = 1 ]; then
  state=idle
  sfile="$state_dir/$session_id"
  [ -f "$sfile" ] && state=$(head -n 1 "$sfile")

  blink=$((now % 2))
  case "$state" in
    working) light="🟢"; [ "$blink" -eq 0 ] && light="⚪" ;;
    waiting) light="🔴"; [ "$blink" -eq 0 ] && light="⚪" ;;
    *)       light="🟡" ;;
  esac

  if [ "$VITALS_IDLE_TIME" = 1 ] && [ "$state" != working ] && [ -f "$sfile" ]; then
    mt=$(stat -f %m "$sfile" 2>/dev/null)
    [ -n "$mt" ] && light="$light $(fmt_age $((now - mt)))"
  fi
  parts+=("$light")
fi

# ---- Modelo ----
[ "$VITALS_MODEL" = 1 ] && parts+=("$model")

# ---- Contexto, en rojo a partir de VITALS_CTX_ALERT% usado ----
if [ "$VITALS_CTX" = 1 ]; then
  if [ "$remaining" != "-" ]; then
    remaining_int=$(printf "%.0f" "$remaining")
    used_int=$(printf "%.0f" "$used")
    ctx_part="ctx ${used_int}% used | ${remaining_int}% left"
    if [ "$used_int" -ge "$VITALS_CTX_ALERT" ]; then
      ctx_part=$'\033[1;31m'"${ctx_part} ⚠"$'\033[0m'
    fi
  else
    ctx_part="ctx --"
  fi
  parts+=("$ctx_part")
fi

# ---- Costo de la sesión ----
if [ "$VITALS_COST" = 1 ] && [ "$cost" != "-" ]; then
  cost_part=$(printf '$%.2f' "$cost" 2>/dev/null) && parts+=("$cost_part")
fi

# ---- Rama git + '*' si hay cambios sin commitear ----
# git status puede ser caro en repos grandes; se cachea por sesión unos segundos.
if [ "$VITALS_GIT" = 1 ] && [ -d "$cwd" ]; then
  gcache="$state_dir/${session_id}.git"
  git_part=""
  if [ -f "$gcache" ] && [ $((now - $(stat -f %m "$gcache" 2>/dev/null || echo 0))) -lt "$VITALS_GIT_CACHE_SECS" ]; then
    git_part=$(cat "$gcache")
  else
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    if [ -n "$branch" ]; then
      dirty=""
      [ -n "$(git -C "$cwd" status --porcelain -uno 2>/dev/null | head -n 1)" ] && dirty="*"
      git_part="⎇ ${branch}${dirty}"
    fi
    mkdir -p "$state_dir" && printf '%s' "$git_part" >"$gcache"
  fi
  [ -n "$git_part" ] && parts+=("$git_part")
fi

# ---- Remote Control: Claude Code exporta CLAUDE_CODE_BRIDGE_SESSION_ID a los
# subprocesos de la statusline solo mientras el bridge está conectado (v2.1.199+).
# CLAUDE_CODE_REMOTE_SESSION_ID es el equivalente en sesiones cloud.
if [ "$VITALS_RC" = 1 ] && { [ -n "$CLAUDE_CODE_BRIDGE_SESSION_ID" ] || [ -n "$CLAUDE_CODE_REMOTE_SESSION_ID" ]; }; then
  parts+=("📡 rc")
fi

# ---- Armar la línea ----
out=""
for p in "${parts[@]}"; do
  [ -n "$out" ] && out+="  |  "
  out+="$p"
done
printf '%s' "$out"
