#!/usr/bin/env bash
# claude-vitals — statusline de Claude Code.
# Muestra: semáforo de actividad, modelo, contexto, costo de la sesión y rama git.
# Módulos configurables en ~/.claude/vitals.conf (ver vitals.conf.example).
# Also forwards data to spacecake if running inside a spacecake terminal.

input=$(cat)

configDir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# ---- Config: vitals.conf > variables de entorno > defaults ----
# shellcheck source=/dev/null
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
: "${VITALS_AUDIT:=1}"
: "${VITALS_AUDIT_CACHE_SECS:=15}"
: "${VITALS_AI_BADGE:=1}"
: "${VITALS_AI_TTL_HOURS:=5}"
: "${VITALS_WINDOW_BG:=1}"
: "${VITALS_BADGE:=1}"
: "${VITALS_BG_WAITING:=4a1015}"
: "${VITALS_BG_WORKING:=0f2a18}"
: "${VITALS_BG_IDLE:=2e2408}"
: "${VITALS_BADGE_TEXT:=ESPERA}"
: "${VITALS_HERDR_METADATA:=1}"
: "${VITALS_HERDR_METADATA_TTL_MS:=5000}"

# Librería compartida (resolviendo el symlink de la statusline)
self="$0"; [ -L "$self" ] && self="$(readlink "$self")"
libfile="$(cd "$(dirname "$self")" && pwd)/vitals-lib.sh"
# shellcheck source=/dev/null
[ -f "$libfile" ] && . "$libfile"

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

# ---- Alta y relleno del archivo de estado ----
# Dos huecos que solo la statusline puede tapar, porque es lo único que corre en
# toda sesión viva:
#   a) una sesión abierta antes de instalar los hooks no tiene archivo, así que
#      quedaba invisible para `vitals` mientras sus caches se acumulaban;
#   b) una escrita por una versión anterior lo tiene sin la identidad de la
#      ventana ni el PID (líneas 3 y 4), que son las que hacen posible `vitals go`;
#   c) una escrita antes de que la sesión pasara a vivir en un panel de herdr
#      lleva en la línea 3 el UUID de iTerm2, que dentro de herdr es el mismo
#      para todos los paneles y por tanto no sirve para saltar a ninguno.
# Los casos (b) y (c) importan sobre todo en las sesiones que te esperan: no van
# a disparar otro hook hasta que les respondas, y para responderles necesitas
# poder saltar a ellas.
# Al rellenar se preserva el mtime: es el reloj del tiempo detenido.
if [ "$session_id" != "-" ] && type vitals_claude_pid >/dev/null 2>&1; then
  sfile0="$state_dir/$session_id"
  want3="$(vitals_session_target)"
  if [ ! -f "$sfile0" ]; then
    mkdir -p "$state_dir"
    printf 'idle\n%s\n%s\n%s\n' \
      "$cwd" "$want3" "$(vitals_claude_pid)" >"$sfile0"
  elif { [ -n "$want3" ] && [ "$(sed -n 3p "$sfile0")" != "$want3" ]; } ||
       [ -z "$(sed -n 4p "$sfile0")" ]; then
    # La identidad solo se pisa cuando hay una mejor que escribir: si esta
    # sesión no sabe la suya (want3 vacío), se conserva la que ya estaba.
    l1=$(sed -n 1p "$sfile0"); l2=$(sed -n 2p "$sfile0")
    keep_mt=$(stat -f %m "$sfile0" 2>/dev/null)
    [ -n "$l1" ] || l1=idle
    [ -n "$l2" ] || l2="$cwd"
    [ -n "$want3" ] || want3=$(sed -n 3p "$sfile0")
    printf '%s\n%s\n%s\n%s\n' \
      "$l1" "$l2" "$want3" "$(vitals_claude_pid)" >"$sfile0"
    [ -n "$keep_mt" ] && touch -m -t "$(date -r "$keep_mt" '+%Y%m%d%H%M.%S')" "$sfile0"
  fi
  # El socket de herdr y la app dueña de su ventana, para que `vitals go` siga
  # funcionando cuando lo dispara SwiftBar sin el entorno del panel.
  vitals_herdr_sidecar_write "$sfile0.herdr"
fi

# ---- Estado de la sesión, escrito por vitals-hook.sh ----
state=idle
sfile="$state_dir/$session_id"
[ -f "$sfile" ] && state=$(head -n 1 "$sfile")

parts=()

# ---- Semáforo ----
# working parpadea verde, waiting parpadea rojo (requiere statusLine.refreshInterval),
# idle queda amarillo fijo con el tiempo que lleva detenido.
if [ "$VITALS_SEMAFORO" = 1 ]; then
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

# ---- Reconciliación de las señales visuales de la ventana ----
# El hook las aplica en el momento del evento, pero eso deja huecos: una sesión
# que cambió de estado antes de instalar esta versión nunca se pintó, y si la
# escritura al terminal falla la ventana queda con el color que no toca.
# Aquí se compara cada refresco el estado real contra lo aplicado y se corrige.
# El fondo distingue los tres estados; el badge solo aparece en waiting, que es
# el único que necesita que sepas de qué proyecto se trata sin entrar.
if type vitals_bg_sync >/dev/null 2>&1; then
  [ "$VITALS_WINDOW_BG" = 1 ] && vitals_bg_sync "$state" "$state_dir/${session_id}.bg"
  if [ "$VITALS_BADGE" = 1 ]; then
    bmark="$state_dir/${session_id}.badge"
    if [ "$state" = waiting ] && [ ! -f "$bmark" ]; then
      vitals_badge_set "$VITALS_BADGE_TEXT
$(basename "$cwd")" && : >"$bmark"
    elif [ "$state" != waiting ] && [ -f "$bmark" ]; then
      vitals_badge_clear && rm -f "$bmark"
    fi
  fi
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

# ---- tri-audit: fase actual de la auditoría 3-IA del workspace, si hay una ----
# STOP y el gate pre-deploy se resaltan porque esperan decisión humana.
if [ "$VITALS_AUDIT" = 1 ] && [ -d "$cwd" ] && type vitals_audit_badge >/dev/null 2>&1; then
  acache="$state_dir/${session_id}.audit"
  if [ -f "$acache" ] && [ $((now - $(stat -f %m "$acache" 2>/dev/null || echo 0))) -lt "$VITALS_AUDIT_CACHE_SECS" ]; then
    badge=$(cat "$acache")
  else
    badge=$(vitals_audit_badge "$cwd")
    mkdir -p "$state_dir" && printf '%s' "$badge" >"$acache"
  fi
  case "$badge" in
    "") : ;;
    STOP*)   parts+=($'\033[1;31m'"⚖ $badge"$'\033[0m') ;;
    *gate*)  parts+=($'\033[1;33m'"⚖ $badge"$'\033[0m') ;;
    OK)      parts+=("⚖ ✓") ;;
    *)       parts+=("⚖ $badge") ;;
  esac
fi

# ---- Badge 3IA: salud de las cuentas de tri-audit (Claude/Codex/Gemini) ----
# La statusline NUNCA llama a las IAs: muestra el cache del último
# `vitals ai --live` y, si tiene más de VITALS_AI_TTL_HOURS, dispara un
# refresco en background (una sola vez, con candado compartido entre sesiones).
if [ "$VITALS_AI_BADGE" = 1 ] && [ -f "$libfile" ]; then
  ai_cache="$state_dir/ai-health"
  ai_ttl=$((VITALS_AI_TTL_HOURS * 3600))
  ai_age=$((now - $(stat -f %m "$ai_cache" 2>/dev/null || echo 0)))
  if [ "$ai_age" -ge "$ai_ttl" ]; then
    lock="$state_dir/ai-refresh.lock"
    lock_age=$((now - $(stat -f %m "$lock" 2>/dev/null || echo 0)))
    # candado vencido (>10 min) = refresco anterior murió; se limpia
    [ -d "$lock" ] && [ "$lock_age" -gt 600 ] && rmdir "$lock" 2>/dev/null
    if mkdir "$lock" 2>/dev/null; then
      ( "$(dirname "$libfile")/vitals" ai --live >/dev/null 2>&1; rmdir "$lock" 2>/dev/null ) &
    fi
  fi
  if [ -f "$ai_cache" ]; then
    read -r ai_line <"$ai_cache"
    ai_fails=""
    for tok in $ai_line; do
      case "$tok" in *:OK:*) : ;; *) ai_fails+="${tok%%:*} " ;; esac
    done
    if [ -z "$ai_fails" ]; then
      parts+=("3IA ✓")
    else
      parts+=($'\033[1;31m'"3IA ✗ ${ai_fails% }"$'\033[0m')
    fi
  fi
fi

# ---- Remote Control: Claude Code exporta CLAUDE_CODE_BRIDGE_SESSION_ID a los
# subprocesos de la statusline solo mientras el bridge está conectado (v2.1.199+).
# CLAUDE_CODE_REMOTE_SESSION_ID es el equivalente en sesiones cloud.
if [ "$VITALS_RC" = 1 ] && { [ -n "$CLAUDE_CODE_BRIDGE_SESSION_ID" ] || [ -n "$CLAUDE_CODE_REMOTE_SESSION_ID" ]; }; then
  parts+=("📡 rc")
fi

# ---- Telemetría al sidebar de herdr -----------------------------------------
# El reparto es limpio: herdr sabe dónde vive cada panel, y lo que pasa dentro
# solo lo sabe vitals. Contexto, costo y salud de las 3 IAs se publican por la
# puerta oficial de metadata, con TTL corto y sin caché.
# El TTL es la respuesta al criterio de que un panel muerto no congele datos
# viejos: se midió que con --ttl-ms 3000 los tokens están a t+1s y ya no están
# a t+5s. Y es también la razón de no cachear: el dato tiene que reescribirse
# más rápido de lo que caduca. Cuesta unos 5 ms, así que con catorce sesiones
# a una llamada por segundo son unos 70 ms/s repartidos entre todas.
# Va en segundo plano para que un socket lento no congele la statusline; el
# fallo no se pierde por eso, vitals_herdr lo deja en herdr.log.
if [ "$VITALS_HERDR_METADATA" = 1 ] && type vitals_herdr >/dev/null 2>&1 &&
   vitals_in_herdr && [ -n "${HERDR_PANE_ID:-}" ]; then
  ctx_tok="--"
  [ "$remaining" != "-" ] && ctx_tok="$(printf '%.0f' "$remaining")% libre"
  cost_tok="--"
  [ "$cost" != "-" ] && cost_tok="$(printf '$%.2f' "$cost" 2>/dev/null)"
  # El mismo cache que alimenta el badge 3IA, leído aquí sin volver a llamar a
  # ninguna IA. Sin cache todavía, se publica "--": no se inventa un ✓.
  ia_tok="--"
  if [ -f "$state_dir/ai-health" ]; then
    read -r ia_line3 <"$state_dir/ai-health"
    ia_tok="✓"
    for tok3 in $ia_line3; do
      case "$tok3" in *:OK:*) : ;; *) ia_tok="✗ ${tok3%%:*}" ;; esac
    done
  fi
  vitals_herdr "$state_dir/herdr.log" pane report-metadata "$HERDR_PANE_ID" \
    --source vitals --ttl-ms "$VITALS_HERDR_METADATA_TTL_MS" \
    --token "ctx=$ctx_tok" --token "cost=$cost_tok" --token "ia=$ia_tok" &
fi

# ---- Armar la línea ----
out=""
for p in "${parts[@]}"; do
  [ -n "$out" ] && out+="  |  "
  out+="$p"
done
printf '%s' "$out"
