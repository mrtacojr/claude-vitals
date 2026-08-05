# claude-vitals

Signos vitales de tus sesiones de [Claude Code](https://claude.com/claude-code), pensado para cuando trabajas en **muchos proyectos a la vez**: cada terminal te dice de un vistazo si Claude está trabajando, detenido, o esperándote — y si te espera, te busca él a ti.

![demo](docs/demo.svg)

## Qué hace

**En la statusline de cada terminal:**

- **Semáforo de actividad**: 🟢 parpadeando = trabajando · 🔴 parpadeando = **esperando tu respuesta** (permiso o pregunta) · 🟡 = detenida, con el tiempo que lleva así (`🟡 25m`)
- **Modelo** en uso
- **Contexto** usado/restante — se pinta **rojo con ⚠** al superar el umbral (default 80%)
- **Costo** acumulado de la sesión en USD
- **Rama git** del workspace, con `*` si hay cambios sin commitear

**Fuera de la statusline:**

- **Color del tab de iTerm2** según el estado (verde/amarillo/rojo) — visible de lejos con muchas ventanas abiertas
- **Notificación de macOS** si una sesión lleva más de N segundos esperando tu respuesta (default 10s, anti-ruido)
- **CLI `vitals`**: resumen de todas las sesiones de la máquina:

```
$ vitals
🔴 esperando   nxt-cotizador   2m     (necesita tu respuesta)
🟢 trabajando  apollo          8s
🟡 detenida    tri-audit       25m

── 3 sesiones: 1 trabajando · 1 esperándote · 1 detenidas
```

## Cómo funciona

Tres piezas:

1. **`vitals.sh`** (statusline): Claude Code invoca el comando configurado en `statusLine` de `~/.claude/settings.json` en cada refresco, pasándole un JSON por stdin (modelo, ventana de contexto, costo, session_id, workspace...). Con `refreshInterval: 1` se re-ejecuta cada segundo, lo que permite el parpadeo y el conteo de tiempo detenido. La consulta a git se cachea unos segundos para no castigar repos grandes.

2. **`vitals-hook.sh`** (hooks): invocado en los eventos del ciclo de vida de cada sesión. Escribe el estado en `~/.claude/vitals-state/<session_id>` (línea 1: estado, línea 2: directorio del proyecto), pinta el tab de iTerm2 y dispara la notificación de macOS:
   - `UserPromptSubmit` / `PostToolUse` → `working` (verde)
   - `Stop` / `SessionStart` → `idle` (amarillo)
   - `Notification` → `waiting` (rojo) + notificación si sigue esperando tras `VITALS_NOTIFY_DELAY`
   - `SessionEnd` → borra el estado y restaura el tab

3. **`vitals`** (CLI): lee `~/.claude/vitals-state/` y lista todas las sesiones, las que te esperan primero.

## Instalación

```bash
git clone https://github.com/mrtacojr/claude-vitals.git
cd claude-vitals
ln -sf "$(pwd)/vitals.sh" ~/.claude/statusline-command.sh
ln -sf "$(pwd)/vitals-hook.sh" ~/.claude/vitals-hook.sh
ln -sf "$(pwd)/vitals" /usr/local/bin/vitals   # o cualquier dir de tu PATH
```

Y en `~/.claude/settings.json` configura la statusline y los hooks (si ya tienes hooks propios, agrega las entradas de vitals junto a las tuyas, no las reemplaces):

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh",
    "refreshInterval": 1
  },
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "$HOME/.claude/vitals-hook.sh", "async": true, "timeout": 5 }] }],
    "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "$HOME/.claude/vitals-hook.sh", "async": true, "timeout": 5 }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "$HOME/.claude/vitals-hook.sh", "async": true, "timeout": 5 }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "$HOME/.claude/vitals-hook.sh", "async": true, "timeout": 5 }] }],
    "SessionStart":     [{ "hooks": [{ "type": "command", "command": "$HOME/.claude/vitals-hook.sh", "async": true, "timeout": 5 }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "$HOME/.claude/vitals-hook.sh", "async": true, "timeout": 5 }] }]
  }
}
```

Las sesiones abiertas toman los hooks al reiniciarlas. Nota: la primera notificación puede requerir que autorices "Script Editor"/osascript en Ajustes → Notificaciones.

## Configuración

Todo es opcional y viene encendido por defecto. Para cambiar algo:

```bash
cp vitals.conf.example ~/.claude/vitals.conf
```

y descomenta lo que quieras: apagar módulos (`VITALS_COST=0`), cambiar el umbral de alerta de contexto (`VITALS_CTX_ALERT=90`), el retraso de la notificación (`VITALS_NOTIFY_DELAY=30`), etc. Ver [`vitals.conf.example`](vitals.conf.example).

## Requisitos

- macOS (color de tab: iTerm2; notificaciones: `osascript`) — la statusline y el CLI funcionan en cualquier terminal con `bash` y `jq`
- `jq`

## Ideas / pendientes

- [x] Semáforo de actividad por sesión (verde/amarillo/rojo + color de tab en iTerm2)
- [x] Costo de la sesión
- [x] Rama de git del workspace con indicador de cambios
- [x] Alerta de contexto alto
- [x] Tiempo detenido
- [x] Notificación de macOS cuando Claude espera tu respuesta
- [x] CLI `vitals` con el resumen de todas las sesiones
- [x] Configuración por módulos
- [ ] `vitals --watch` (refresco en vivo del resumen)
- [ ] Soporte para tab color en otras terminales (kitty, WezTerm)
- [ ] Historial de costo por proyecto

## Contribuir

Issues y PRs son bienvenidos. La única regla: la salida debe caber en una línea de terminal.

## Licencia

[MIT](LICENSE)
