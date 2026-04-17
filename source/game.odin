/*
This file is the starting point of your game.

Some important procedures are:
- game_init_window: Opens the window
- game_init: Sets up the game state
- game_update: Run once per frame
- game_should_close: For stopping your game when close button is pressed
- game_shutdown: Shuts down game and frees memory
- game_shutdown_window: Closes window

The procs above are used regardless if you compile using the `build_release`
script or the `build_hot_reload` script. However, in the hot reload case, the
contents of this file is compiled as part of `build/hot_reload/game.dll` (or
.dylib/.so on mac/linux). In the hot reload cases some other procedures are
also used in order to facilitate the hot reload functionality:

- game_memory: Run just before a hot reload. That way game_hot_reload.exe has a
	pointer to the game's memory that it can hand to the new game DLL.
- game_hot_reloaded: Run after a hot reload so that the `g` global
	variable can be set to whatever pointer it was in the old DLL.

NOTE: When compiled as part of `build_release`, `build_debug` or `build_web`
then this whole package is just treated as a normal Odin package. No DLL is
created.
*/

package game

import "core:fmt"
import "core:math/linalg"
import rl "vendor:raylib"

PIXEL_WINDOW_HEIGHT :: 180

Debug_State :: struct {
	show_overlay: bool,
	paused:       bool,
	player_speed: f32,
	debug_draw:   bool,
}


// Doesn't contain any "meta" state like
// inputs and debug state
Game_State :: struct {
	player_pos: rl.Vector2,
}


Game_Memory :: struct {
	//render_texture : rl.RenderTexture2D,
	old_input_state : All_Input_State,
	input_state : All_Input_State,
	irs : Input_Recording_State,
	gs : Game_State,
	run: bool,
	debug: Debug_State,
}

g: ^Game_Memory

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	return {
		zoom = h/PIXEL_WINDOW_HEIGHT,
		// Fixed camera anchored at world origin so the player visibly moves on
		// screen. Change `target` to `g.gs.player_pos` for a follow-cam.
		target = {0, 0},
		offset = { w/2, h/2 },
	}
}

update :: proc() {

	if rl.IsKeyPressed(.F3) do g.debug.show_overlay = !g.debug.show_overlay
	if rl.IsKeyPressed(.F4) do g.debug.paused = !g.debug.paused

	if rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}

	if g.debug.paused do return

	input: rl.Vector2

	if IsKeyDown(.UP) || IsKeyDown(.W) {
		input.y -= 1
	}
	if IsKeyDown(.DOWN) || IsKeyDown(.S) {
		input.y += 1
	}
	if IsKeyDown(.LEFT) || IsKeyDown(.A) {
		input.x -= 1
	}
	if IsKeyDown(.RIGHT) || IsKeyDown(.D) {
		input.x += 1
	}

	input = linalg.normalize0(input)
	g.gs.player_pos += input * rl.GetFrameTime() * g.debug.player_speed
}

draw_debug_overlay :: proc() {
	if !g.debug.show_overlay do return

	rl.GuiPanel({8, 8, 240, 200}, "debug  [F3 hide  F4 pause]")

	rl.DrawText(fmt.ctprintf("%d fps", rl.GetFPS()),                        16, 40, 10, rl.BLACK)
	rl.DrawText(fmt.ctprintf("pos %.1f, %.1f", g.gs.player_pos.x, g.gs.player_pos.y), 16, 56, 10, rl.BLACK)
	if g.debug.paused {
		rl.DrawText("PAUSED", 200, 40, 10, rl.MAROON)
	}

	rl.GuiSlider(
		{70, 96, 120, 16},
		"speed",
		fmt.ctprintf("%.0f", g.debug.player_speed),
		&g.debug.player_speed,
		0, 400,
	)

	if rl.GuiButton({16, 124, 100, 20}, "reset pos") {
		g.gs.player_pos = {}
	}
	rl.GuiCheckBox({16, 156, 16, 16}, "draw debug", &g.debug.debug_draw)
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLUE)

	rl.BeginMode2D(game_camera())
	rl.DrawRectangleV(g.gs.player_pos, {16, 16}, rl.RAYWHITE)

	if g.debug.debug_draw {
		rl.DrawRectangleLinesEx({g.gs.player_pos.x, g.gs.player_pos.y, 16, 16}, 1, rl.MAGENTA)
		rl.DrawLineV({-5, 0}, {5, 0}, rl.YELLOW)
		rl.DrawLineV({0, -5}, {0, 5}, rl.YELLOW)
	}
	rl.EndMode2D()

	// Debug overlay is drawn in screen space (no camera) so its controls sit
	// on top of everything. `fmt.ctprintf` uses the temp allocator, which is
	// freed at end-of-frame by the host in main_hot_reload.odin /
	// main_release.odin / main_web_entry.odin.
	draw_debug_overlay()

	rl.EndDrawing()
}

@(export)
game_update :: proc() {
	// RECORD THEN IMMEDIATELY PLAYBACK
	if rl.IsKeyPressed(.L) {
		if g.irs.is_playback {
			end_input_playback(&g.irs)
			g.old_input_state = {}
		} else if g.irs.is_recording {
			end_recording_input(&g.irs)
			begin_input_playback(&g.irs, &g.gs)
			g.irs.playback_frame = 0
		} else if !g.irs.is_recording && !g.irs.is_playback {
			begin_recording_input(&g.irs, &g.gs)			
		}
	}

	update_all_input_state()

	if g.irs.is_playback {
		playback_input(&g.irs, &g.gs, &g.input_state)
	} else if g.irs.is_recording {
		record_input(&g.irs, &g.input_state)
	}

	g.old_input_state = g.input_state
	
	update()
	draw()

	// Everything on tracking allocator is valid until end-of-frame.
	free_all(context.temp_allocator)
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "Cabin Jam 2026")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(60)
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	g = new(Game_Memory)

	g^ = Game_Memory {
		run = true,
		debug = { show_overlay = true, player_speed = 100 },
	}

	game_hot_reloaded(g)
}

@(export)
game_should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			return false
		}
	}

	return g.run
}

@(export)
game_shutdown :: proc() {
	free(g)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside `g`.
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}
