# claude-vitals

Statusline personalizada para [Claude Code](https://claude.com/claude-code): muestra los "signos vitales" de la sesión en la barra de estado de la terminal.

```
Fable 5  |  ctx 14% used | 86% left
```

## Qué muestra hoy

- **Modelo** en uso (`.model.display_name`)
- **Contexto** usado/restante en porcentaje (`.context_window`)
- Reenvío del JSON completo a **spacecake** vía unix socket, si la terminal es spacecake

## Cómo funciona

Claude Code invoca el comando configurado en `statusLine` de `~/.claude/settings.json` en cada refresco, pasándole un JSON por stdin con datos de la sesión (modelo, ventana de contexto, workspace, costo, etc.). El script extrae lo que le interesa con `jq` e imprime una línea; eso es lo que se ve en la barra.

## Instalación

Clona el repo y crea un symlink para que Claude Code use el script:

```bash
git clone https://github.com/mrtacojr/claude-vitals.git
cd claude-vitals
ln -sf "$(pwd)/vitals.sh" ~/.claude/statusline-command.sh
```

Y en `~/.claude/settings.json` apunta la statusline al symlink:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.sh"
  }
}
```

Así, cualquier cambio en el repo se refleja en vivo en la statusline.

## Requisitos

- `jq`
- `bash`

## Ideas / pendientes

- [ ] Costo de la sesión
- [ ] Rama de git del workspace
- [ ] Colores / iconos según % de contexto

## Contribuir

Issues y PRs son bienvenidos. La única regla: la salida debe caber en una línea de terminal.

## Licencia

[MIT](LICENSE)
