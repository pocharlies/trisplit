# Trisplit — diseño

Fecha: 2026-09-16 · Plataforma: macOS 26.2 · Motor: Hammerspoon 1.1.1 (Lua)

## Objetivo

Dividir la pantalla principal en 3 columnas iguales y colocar 3 apps elegidas, sin hacerlo a mano. Dos formas de activarlo:

1. **Preset con hotkey** — `⌘⌥3` aplica el preset `dev3` (OpenChamber, VS Code, Claude). Lanza las apps que no estén abiertas y restaura las minimizadas.
2. **Picker** — `⌘⌥⇧3` abre un buscador estilo Spotlight; se eligen 3 apps de una (las instaladas en /Applications) y se colocan en 3 columnas.

## Decisiones del usuario

- Ambos modos (preset + picker).
- División horizontal: 3 columnas de igual ancho.
- Pantalla objetivo: Odyssey G95C (ultrawide superior, configurable vía `PREFERRED_SCREEN`; fallback a la pantalla de mayor área).

## Arquitectura

Un único módulo Lua cargado desde `~/.hammerspoon/init.lua` (symlink al repo):

- `presets`: tabla de presets; cada preset es una lista de entradas, cada entrada una lista de nombres candidatos (nombre de proceso y/o nombre de .app) para tolerar discrepancias (ej. `Code` vs `Visual Studio Code`).
- `ensureRunning(names)`: devuelve la app si ya corre; si no, `launchOrFocus` y sondea hasta 5 s.
- `placeApp(name, frame)`: consigue ventana estándar (o desminimiza), `setFrame` con animación.
- `columnFrames(n)`: divide `frame()` (el área visible, sin Dock ni barra de menú) de `hs.screen.mainScreen()` en n columnas iguales con separación de 4 px.
- `applyLayout(listOfNames)`: orquesta ensureRunning + placeApp por posición.
- **Picker**: `hs.chooser` re-entrante — prompt "App 1 de 3", "App 2 de 3", "App 3 de 3"; Esc cancela; al completar aplica el layout.
- **Menu bar**: icono `◫3` con los presets y "Elegir 3 apps…".
- **Hotkeys**: `⌘⌥3` preset dev3, `⌘⌥⇧3` picker.
- `hs.ipc` habilitado para poder verificar/invocar desde CLI (`hs -c`).

## Errores

- Pantalla bloqueada (frontmost = loginwindow) → `applyLayout` aborta y lo registra: con el lock activo las subroles AX se vacían y los frames no son fiables.
- App no encontrada en 5 s → se registra en el log de Hammerspoon y se omite (las demás se colocan igualmente).
- App sin ventana en el Space actual → se activa la app (cambia de Space) y se reintenta.
- App corriendo sin ventana (Claude en menu bar) → `launchOrFocus`; si sigue sin ventana → `kill -9` + relanzar (Claude ignora forceTerminate de NSRunningApplication).
- Sin permiso de Accesibilidad → los `setFrame` no hacen efecto y `allWindows()` devuelve 0 silenciosamente; Hammerspoon lo pide al arrancar.

## Verificación (realizada 2026-09-16)

- Preset dev3 aplicado vía `hs -c "trisplit.applyPreset('dev3')"`: OpenChamber (0,-1410 1704x1410), Code (1708,-1410), Claude (3416,-1410) — 3 columnas exactas (1704 = (5120−8)/3) sobre Odyssey G95C.
- 2 hotkeys registrados; picker hs.chooser abre y cierra sin errores.

## Fuera de alcance (YAGNI)

- 3 franjas verticales, grids 2x2, presets multi-pantalla, guardar/restaurar layouts, arrastrar ventanas.

