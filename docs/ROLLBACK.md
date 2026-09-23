# Rollback: Trisplit v2 (native) -> v1 (Hammerspoon)

Migration done 2026-09-23. Full pre-migration backup of `~/.hammerspoon`:
`~/.hammerspoon-backup-20260923-190313` (legacy `trisplit.json` sha256 `997494ac8b10e6cc…`).

Run in order:

```bash
# 1. Unregister the v2 login item
~/Applications/Trisplit.app/Contents/MacOS/Trisplit --login-item off

# 2. Quit v2
osascript -e 'quit app "Trisplit"' || pkill -x Trisplit

# 3. Restore the v1 config (drop the stub). Pick ONE:
#   a) symlink to the in-repo copy (v1 now lives in legacy/)
rm ~/.hammerspoon/init.lua && mv ~/.hammerspoon/init.lua.trisplit-v1-disabled ~/.hammerspoon/init.lua
ls -la ~/.hammerspoon/init.lua   # -> .../trisplit/legacy/init.lua
#   b) plain copy from the tag
#   (ejecutar desde la raíz del repo)
git -C "$(pwd)" show v1-hammerspoon:init.lua > ~/.hammerspoon/init.lua

# 4. Relaunch Hammerspoon
open -a Hammerspoon
```

v1 loads `panel.html`/`icon.png` from the repo root (current v2 `panel.html`) and, with no
`TrisplitPanel.app` on disk, uses its built-in webview fallback. For a byte-exact v1 tree
(including the old `TrisplitPanel.app` sources), use a worktree of the tag:
`git worktree add ~/trisplit-v1 v1-hammerspoon` and point the symlink at `~/trisplit-v1/init.lua`.
v1 Lua tests are in `legacy/tests/` (need a running Hammerspoon).

Optional cleanup of v2:

```bash
rm -rf ~/Applications/Trisplit.app
rm -rf ~/Library/Application\ Support/trisplit   # v2 state (imported copy of the legacy file)
```

If `~/.hammerspoon` is damaged, restore it wholesale from the backup:
`rm -rf ~/.hammerspoon && cp -a ~/.hammerspoon-backup-20260923-190313 ~/.hammerspoon`

## Coexistence

`isTrisplitV1Config()` (`app/Core/Coexistence.swift`) treats v1 as active only when Hammerspoon
is running AND `~/.hammerspoon/init.lua` is a symlink into the trisplit repo, or contains
`hs.hotkey.bind` plus "trisplit". The migration stub matches neither, so v2 keeps its hotkeys.
After rollback (a) or (b), v2 skips its hotkeys while Hammerspoon runs (override:
`TRISPLIT_FORCE_HOTKEYS=1`).
