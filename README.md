# trisplit

Panel visual estilo macOS para colocar apps en **rejillas por monitor** (columnas × filas configurables) y aplicar layouts con un hotkey. Arrastrar un slot **mueve la ventana real al instante**.

## Uso

| Acción | Atajo |
|---|---|
| Aplicar la configuración activa (todos los monitores) | `⌘⌥0` |
| Cambiar a la siguiente configuración y aplicarla | `⌘⌥⇧0` |
| Abrir el panel | `⌘⌥P` (o icono ▥ de la barra de menú) |
| Mover la ventana frontal al hueco N | `⌘⌥1` … `⌘⌥9` |
| Enfocar la app del hueco N | `⌘⌥⇧1` … `⌘⌥⇧9` |

El número N de cada hueco aparece en su etiqueta `⌘⌥N` del panel (los huecos se numeran de izquierda a derecha y de arriba abajo, monitor a monitor).

## Panel

- Cada monitor se muestra a escala con steppers **col / fil** para elegir su rejilla (1–6 columnas × 1–4 filas).
- **Arrastra apps** desde la bandeja inferior (o entre huecos, incluso de monitores distintos): la ventana real se mueve a la celda al soltar.
- Doble clic en una app de la bandeja → la coloca en el primer hueco libre.
- Varias configuraciones (Dev, Reunión, …) con selector, ＋ y 🗑; se autoguardan en `~/.hammerspoon/trisplit.json`.
- Esc o "Cerrar" cierra el panel.

## Por dentro

- `init.lua` (Hammerspoon/Lua): estado JSON, colocación (lanza apps, saca de otros Spaces, sale de fullscreen, reinicia apps sin ventana), hotkeys, panel `hs.webview`.
- `panel.html`: UI ligera estilo macOS (claro, system font), drag & drop HTML5.
- CLI: `hs -c "trisplit.apply()"`, `trisplit.liveMove('Odyssey G95C', 2, 'Code')`, etc.

## Requisitos

- Hammerspoon 1.1.x con permiso de **Accesibilidad** (Ajustes → Privacidad → Accesibilidad).
- Autostart ya activado (`hs.autoLaunch`).
