# Cabin Jam 2026

Odin + Raylib starter with hot reload, save-triggered rebuilds, and an in-game debug overlay. Ships as native desktop (macOS, Windows) and web (itch.io) at 1280×720.

Built on top of [karl-zylinski/odin-raylib-hot-reload-game-template](https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template) (MIT). See `LICENSE`.

## Requirements

- [Odin](https://odin-lang.org) compiler on `PATH`.
- **macOS:** [fswatch](https://github.com/emcrisostomo/fswatch) for `watch.sh` — `brew install fswatch`.
- **Windows:** nothing extra — `watch.bat` uses built-in PowerShell.
- **Web build:** [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html).

## Quick start

### macOS

```bash
./build_hot_reload.sh run   # build and launch
./watch.sh                  # in a second terminal: rebuild on save
```

### Windows

```bat
build_hot_reload.bat run
watch.bat
```

### Web

1. Install emsdk. The scripts look in `$HOME/repos/emsdk` (macOS) and `c:\SDK\emsdk` (Windows) by default. If yours lives elsewhere, either edit `EMSCRIPTEN_SDK_DIR` at the top of `build_web.sh` / `.bat`, or just put `emcc` on your `PATH`.
2. `./build_web.sh` or `build_web.bat`.
3. `cd build/web && python3 -m http.server` and open http://localhost:8000.

You can't open `build/web/index.html` directly — browser CORS rules block wasm loading from `file://`.

## In-game controls

| Key | Action |
|-----|--------|
| WASD / arrows | move |
| F3 | toggle debug overlay |
| F4 | pause simulation (overlay stays live) |
| F5 | force hot reload |
| F6 | force full restart (re-runs `game_init`) |
| Esc | quit |

## How hot reload works

`game_hot_reload.bin` / `.exe` is a host that stays running. `source/game.odin` compiles to a shared library (`game.dylib` / `.dll`) in `build/hot_reload/`, and the host reloads it whenever the file changes on disk. `Game_Memory` is preserved across reloads — tweak proc bodies, constants, or add new procs without losing game state.

If you change the **size** of `Game_Memory`, the host detects it and calls `game_init` from scratch. One-time state-reset per struct change.

`watch.sh` / `watch.bat` re-runs the build script on every `.odin` save so the full loop is: save in your editor → game updates in ~1 second.

## Project layout

```
source/
  game.odin                    reloadable game logic
  main_hot_reload/             dev host
  main_release/                desktop release entry
  main_web/                    emscripten entry + JS glue
assets/                        sprites, sounds, music (empty; add yours here)
vendor/raylib/wasm/            prebuilt wasm libs for web build
build_hot_reload.{sh,bat}      dev build
build_release.{sh,bat}         optimized desktop build
build_web.{sh,bat}             wasm build
watch.{sh,bat}                 save-triggered rebuild
ols.json                       OLS config (portable, shared)
project.sublime-project        Sublime Text build system
.zed/launch.json               Zed debug config (gitignored, per-machine)
```

## Editor setup

### Zed (macOS)
Install the `ols` language server. `ols.json` is auto-picked-up; `ols` discovers its `core` / `vendor` collections by running `odin root`. Debug via `.zed/launch.json` (LLDB targeting the hot-reload binary).

### Sublime Text
Install `LSP` + `LSP-odin` via Package Control. Open `project.sublime-project`. `Ctrl/Cmd+B` triggers `build_hot_reload`. Compile errors are click-navigable.

### RAD Debugger (Windows)
Attach to `game_hot_reload.exe` for native debugging with hot reload. The build script outputs a fresh PDB per reload, so the debugger stays in sync across swaps.

## Debug overlay

`draw_debug_overlay` in `source/game.odin` uses raygui (already part of `vendor:raylib`). Values live inside `Debug_State` which is nested in `Game_Memory`, so tunings survive hot reload. Add more controls by extending the struct:

```odin
rl.GuiCheckBox({16, 180, 16, 16}, "god mode", &g.debug.god_mode)
rl.GuiSlider({70, 200, 120, 16}, "spawn rate",
    fmt.ctprintf("%.1fs", g.debug.spawn_rate),
    &g.debug.spawn_rate, 0.1, 5)
```

See `raygui.odin` in Odin's `vendor:raylib` for the full control list.

## Resolution

1280×720 on both desktop and web.

- Desktop: `rl.InitWindow(1280, 720, ...)` in `game_init_window`.
- Web: canvas is locked at 1280×720 in `source/main_web/index_template.html` with `image-rendering: pixelated` and CSS `max-width/height: 100vw/vh` for letterboxed scaling inside itch's iframe.

`PIXEL_WINDOW_HEIGHT :: 180` sets the camera zoom — the game renders as if the viewport were 180 units tall (a 4× upscale at 720p). Tweak this to change the pixel-art feel.

## Shipping

- **Desktop build:** `./build_release.sh` / `build_release.bat` → `build/release/` (optimized, no hot-reload host, assets folder copied alongside the binary).
- **Web build:** `./build_web.sh` / `build_web.bat` → `build/web/`. Zip the contents and upload as an HTML5 build on itch.io.

## Wasm libraries

`vendor/raylib/wasm/libraylib.a` and `libraygui.a` are committed to this repo because Homebrew's Odin package ships an empty `vendor/raylib/wasm/` directory, and other Odin distributions are inconsistent. If the Odin toolchain updates and the raylib ABI shifts, re-fetch from upstream:

```bash
curl -L https://raw.githubusercontent.com/odin-lang/Odin/master/vendor/raylib/wasm/libraylib.a -o vendor/raylib/wasm/libraylib.a
curl -L https://raw.githubusercontent.com/odin-lang/Odin/master/vendor/raylib/wasm/libraygui.a -o vendor/raylib/wasm/libraygui.a
```

## Credit

Template foundation: [karl-zylinski/odin-raylib-hot-reload-game-template](https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template).
Hot-reload design walkthrough: http://zylinski.se/posts/hot-reload-gameplay-code/
