# Odin + Raylib + Hot Reload template

This is an [Odin](https://github.com/odin-lang/Odin) + [Raylib](https://github.com/raysan5/raylib) game template with [Hot Reloading](http://zylinski.se/posts/hot-reload-gameplay-code/) pre-setup. It makes it possible to reload gameplay code while the game is running.

Supported platforms: Windows, macOS, Linux and [web](#web-build).

Supported editors: [Sublime Text](#sublime-text), [Zed](https://zed.dev) on macOS, and [RAD Debugger](#rad-debugger) for Windows native debugging.

![hot_reload gif](https://github.com/user-attachments/assets/18059ab2-0878-4617-971d-e629a969fc93)

See The Legend of Tuna repository for an example project that also uses Box2D: https://github.com/karl-zylinski/the-legend-of-tuna

I used this kind of hot reloading while developing my game [CAT & ONION](https://store.steampowered.com/app/2781210/CAT__ONION/).

## Hot reload quick start

> [!NOTE]
> These instructions use some Windows terminology. If you are on mac / linux, then replace these words:
> - `bat` -> `sh`
> - `exe` -> `bin`
> - `dll` -> `dylib` (mac), `so` (linux)

1. Run `build_hot_reload.bat` to create `game_hot_reload.exe` (located at the root of the project) and `game.dll` (located in `build/hot_reload`). Note: It expects odin compiler to be part of your PATH environment variable.
2. Run `game_hot_reload.exe`, leave it running.
3. Make changes to the gameplay code in `source/game.odin`. For example, change the line `rl.ClearBackground(rl.BLACK)` so that it instead uses `rl.BLUE`. Save the file.
4. Run `build_hot_reload.bat`, it will recompile `game.dll`.
5. The running `game_hot_reload.exe` will see that `game.dll` changed and reload it. But it will use the same `Game_Memory` (a struct defined in `source/game.odin`) as before. This will make the game use your new code without having to restart.

Note, in step 4: `build_hot_reload.bat` does not rebuild `game_hot_reload.exe`. It checks if `game_hot_reload.exe` is already running. If it is, then it skips compiling it.

## Release builds

Run `build_release.bat` to create a release build in `build/release`. That exe does not have the hot reloading stuff, since you probably do not want that in the released version of your game. This means that the release version does not use `game.dll`, instead it imports the `source` folder as a normal Odin package.

`build_debug.bat` is like `build_release.bat` but makes a debuggable executable, in case you need to debug your non-hot-reload-exe.

## Web build

`build_web.bat` builds a release web executable (no hot reloading!).

### Web build requirements

- Emscripten. Download and install somewhere on your computer. Follow the instructions here: https://emscripten.org/docs/getting_started/downloads.html (follow the stuff under "Installation instructions using the emsdk (recommended)").
- Recent Odin compiler: This uses Raylib binding changes that were done on January 1, 2025.

The wasm-compiled Raylib + RayGUI libraries (`vendor/raylib/wasm/libraylib.a` and `libraygui.a`) are committed to this repo because Homebrew's Odin package ships an empty `vendor/raylib/wasm/` directory. If you update the Odin compiler and the ABI changes, re-fetch them from Odin upstream:
```
curl -L https://raw.githubusercontent.com/odin-lang/Odin/master/vendor/raylib/wasm/libraylib.a -o vendor/raylib/wasm/libraylib.a
curl -L https://raw.githubusercontent.com/odin-lang/Odin/master/vendor/raylib/wasm/libraygui.a -o vendor/raylib/wasm/libraygui.a
```

### Web build quick start

1. Point `EMSCRIPTEN_SDK_DIR` in `build_web.bat/sh` to where you installed emscripten.
2. Run `build_web.bat/sh`.
3. Web game is in the `build/web` folder.

> [!NOTE]
> `build_web.bat` is for windows, `build_web.sh` is for Linux / macOS.

> [!WARNING]
> You can't run `build/web/index.html` directly due to "CORS policy" javascript errors. You can work around that by running a small python web server:
> - Go to `build/web` in a console.
> - Run `python -m http.server`
> - Go to `localhost:8000` in your browser.
>
> _For those who don't have python: Emscripten comes with it. See the `python` folder in your emscripten installation directory._

Build a desktop executable using `build_desktop.bat/sh`. It will end up in the `build/desktop` folder.

### Web build troubleshooting

See the README of the [Odin + Raylib on the web repository](https://github.com/karl-zylinski/odin-raylib-web?tab=readme-ov-file#troubleshooting) for troubleshooting steps.

## Assets
You can put assets such as textures, sounds and music in the `assets` folder. That folder will be copied when a release build is created and also integrated into the web build.

The hot reload build doesn't do any copying, because the hot reload executable lives in the root of the repository, alongside the `assets` folder.

## Auto-rebuild on save

A file-watcher script re-runs `build_hot_reload` whenever any `.odin` file under `source/` changes. Leave the game running in one terminal, and the watcher in another:

- **macOS / Linux:** `./watch.sh` (requires `fswatch` — install with `brew install fswatch`)
- **Windows:** `watch.bat` (uses PowerShell's built-in `FileSystemWatcher`, no install)

Saves the manual "go re-run the build script" step on every iteration.

## In-game debug overlay

`source/game.odin` includes a small raygui-based debug overlay with an FPS readout, player state, a speed slider, and a reset button. It lives inside `Game_Memory` so its settings survive hot reload.

- `F3` — toggle the overlay
- `F4` — pause the simulation (overlay stays interactive)

Add more knobs by extending `Debug_State` and `draw_debug_overlay`. Raygui is already part of `vendor:raylib`, so no new dependencies are needed.

## Sublime Text

For those who use Sublime Text there's a project file: `project.sublime-project`.

How to use:
- Open the project file in sublime
- Choose the build system `Main Menu -> Tools -> Build System -> Odin + Raylib + Hot Reload template` (you can rename the build system by editing `project.sublime-project` manually)
- Compile and run by pressing using F7 / Ctrl + B / Cmd + B
- After you make code changes and want to hot reload, just hit F7 / Ctrl + B / Cmd + B again

### Sublime LSP (autocomplete, hover, jump-to-def)

Install the `LSP` and `LSP-odin` packages via Package Control, make sure the `odin` compiler is on your `PATH`, and the committed `ols.json` will be picked up automatically. OLS discovers its `core`/`vendor` collections by invoking `odin root`, so the same file works on macOS, Linux, and Windows.

## RAD Debugger
You can hot reload while attached to [RAD Debugger](https://github.com/EpicGamesExt/raddebugger). Attach to your `game_hot_reload` executable, make code changes in your code editor and re-run the the `build_hot_reload` script to build and hot reload.

## Questions?

Ask questions in my gamedev Discord: https://discord.gg/4FsHgtBmFK

I have a blog post about Hot Reloading here: http://zylinski.se/posts/hot-reload-gameplay-code/

## Have a nice day! /Karl Zylinski
