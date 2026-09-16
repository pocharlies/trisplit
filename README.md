# trisplit

Divide la pantalla en **3 columnas iguales** y coloca 3 apps — sin arrastrar ventanas.

## Uso

| Acción | Atajo |
|---|---|
| Preset `dev3` (OpenChamber · VS Code · Claude) | `⌘⌥3` |
| Elegir 3 apps al vuelo (buscador) | `⌘⌥⇧3` |
| Menú rápido | icono `◫3` en la barra de menú |

- Lanza las apps que no estén abiertas; restaura las minimizadas; saca las de otros Spaces y las fullscreen.
- Claude cerrado a la barra de menú: se reinicia automáticamente para abrir ventana.
- Pantalla objetivo: `PREFERRED_SCREEN` en `init.lua` (actualmente "Odyssey G95C"; fallback: pantalla más grande).

## Personalizar

Edita `~/Documents/ClaudecodeTools/trisplit/init.lua`:

```lua
local presets = {
  dev3 = { { "OpenChamber" }, { "Code", "Visual Studio Code" }, { "Claude" } },
  -- añade más presets aquí
}
```

y recarga con el menú `◫3 → Recargar config` (o `hs -c "hs.reload()"`).

## Instalación

Ya instalada: Hammerspoon + symlink `~/.hammerspoon/init.lua` → este repo + autostart.
Requisito: permiso de Accesibilidad para Hammerspoon (Ajustes → Privacidad → Accesibilidad).

## CLI

`hs -c "trisplit.applyPreset('dev3')"` — utilizable en scripts.
