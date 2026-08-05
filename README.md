# claude-vitals

Statusline personalizada para [Claude Code](https://claude.com/claude-code): muestra los "signos vitales" de la sesión en la barra de estado de la terminal.

```
Fable 5  |  ctx 14% used | 86% left
```

## Qué muestra hoy

- **Semáforo de actividad** por sesión:
  - 🟢 parpadeando — Claude está trabajando en esta terminal
  - 🔴 parpadeando — Claude está **esperando tu respuesta** (permiso o pregunta)
  - 🟡 fijo — sesión detenida / sin actividad
- **Modelo** en uso (`.model.display_name`)
- **Contexto** usado/restante en porcentaje (`.context_window`)
- Reenvío del JSON completo a **spacecake** vía unix socket, si la terminal es spacecake

En iTerm2, el semáforo también **pinta el color del tab** (verde/amarillo/rojo), visible de lejos cuando tienes muchas ventanas abiertas.

## Cómo funciona

Dos piezas:

1. **`vitals.sh`** (statusline): Claude Code invoca el comando configurado en `statusLine` de `~/.claude/settings.json` en cada refresco, pasándole un JSON por stdin con datos de la sesión (modelo, ventana de contexto, session_id, etc.). El script extrae lo que le interesa con `jq` e imprime una línea. Con `refreshInterval: 1` se re-ejecuta cada segundo, lo que permite el parpadeo.

2. **`vitals-hook.sh`** (hooks): Claude Code lo invoca en los eventos del ciclo de vida de cada sesión. Escribe el estado en `~/.claude/vitals-state/<session_id>` (que `vitals.sh` lee) y emite las secuencias de escape de iTerm2 para colorear el tab:
   - `UserPromptSubmit` / `PostToolUse` → `working` (verde)
   - `Stop` / `SessionStart` → `idle` (amarillo)
   - `Notification` → `waiting` (rojo — Claude necesita tu input)
   - `SessionEnd` → borra el estado y restaura el color del tab

## Instalación

Clona el repo y crea un symlink para que Claude Code use el script:

```bash
git clone https://github.com/mrtacojr/claude-vitals.git
cd claude-vitals
ln -sf "$(pwd)/vitals.sh" ~/.claude/statusline-command.sh
ln -sf "$(pwd)/vitals-hook.sh" ~/.claude/vitals-hook.sh
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

Así, cualquier cambio en el repo se refleja en vivo en la statusline.

## Requisitos

- `jq`
- `bash`

## Ideas / pendientes

- [x] Semáforo de actividad por sesión (verde/amarillo/rojo + color de tab en iTerm2)
- [ ] Costo de la sesión
- [ ] Rama de git del workspace
- [ ] Colores / iconos según % de contexto

## Contribuir

Issues y PRs son bienvenidos. La única regla: la salida debe caber en una línea de terminal.

## Licencia

[MIT](LICENSE)
