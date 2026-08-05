# vitals-lib.sh — funciones compartidas entre vitals.sh (statusline) y vitals (CLI).
# Se carga con `source`; no ejecutar directamente.

# Badge de tri-audit (https://github.com/... metodología de contrapeso 3-IA).
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
