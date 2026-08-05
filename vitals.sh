#!/usr/bin/env bash
# Claude Code status line: shows model name and context remaining percentage.
# Also forwards data to spacecake if running inside a spacecake terminal.

input=$(cat)

# Forward to spacecake if applicable (preserves existing integration)
if [ -n "${SPACECAKE_TERMINAL}" ]; then
  configDir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  socketPath="${configDir}/spacecake.sock"
  if [ -S "$socketPath" ]; then
    echo "$input" | curl -s -X POST -H "Content-Type: application/json" -d @- \
      --unix-socket "$socketPath" --max-time 2 \
      http://localhost/statusline >/dev/null 2>&1 &
  fi
fi

# Extract fields
model=$(echo "$input" | jq -r '.model.display_name // "Unknown model"')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Build context portion
if [ -n "$remaining" ]; then
  # Round to integer
  remaining_int=$(printf "%.0f" "$remaining")
  used_int=$(printf "%.0f" "$used")
  ctx_part="ctx ${used_int}% used | ${remaining_int}% left"
else
  ctx_part="ctx --"
fi

printf "%s  |  %s" "$model" "$ctx_part"
