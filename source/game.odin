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



Tile_Type :: enum {
	Trail,
	Solid,
}

tile_size :: 64
chunk_width :: 5
chunk_height :: 5
tiles_in_chunk :: chunk_width * chunk_height

Tilemap_Chunk :: struct {
	tiles : [tiles_in_chunk]int,
}

max_chunks_in_arrangement :: 10

Chunk_Arrangement :: struct {
	chunks : [max_chunks_in_arrangement]Tilemap_Chunk,
	width : int,
	height : int,
}


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
	render_texture : rl.RenderTexture2D,
	old_input_state : All_Input_State,
	input_state : All_Input_State,
	irs : Input_Recording_State,
	gs : Game_State,
	run: bool,
	debug: Debug_State,
}

g: ^Game_Memory

game_camera :: proc() -> rl.Camera2D {
	// w := f32(rl.GetScreenWidth())
	// h := f32(rl.GetScreenHeight())

	w := f32(g.render_texture.texture.width)
	h := f32(g.render_texture.texture.height)

	return {
		zoom = 1.0,
		// Fixed camera anchored at world origin so the player visibly moves on
		// screen. Change `target` to `g.gs.player_pos` for a follow-cam.
		target = {0, 0},
		offset = { w/2, h/2 },
	}
}

update :: proc() {

	// NOTE(john): these are ints in here only because its easy to write in code
	// These are planned to be enum values once
	//... if we have an actual editor where we are placing these things
	tilemap_chunk := Tilemap_Chunk{
		tiles = {
			1,1,1,1,1,
			1,0,0,0,0,
			1,0,1,1,1,
			1,0,1,1,1,
			1,0,1,1,1,
		}
	}

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


	rl.BeginTextureMode(g.render_texture)
	rl.ClearBackground(rl.BLUE)

	chunk_pos := [2]f32 {0, 0}
	for x in 0..<chunk_width {
		for y in 0..<chunk_height {
			i := y*chunk_width + x
			tile_type := tilemap_chunk.tiles[i]
			color := Tile_Type(tile_type) == .Solid ? rl.BLACK : rl.WHITE
			rect := rl.Rectangle {
				chunk_pos.x + (tile_size*f32(x)),
				chunk_pos.y + (tile_size*f32(y)),
				tile_size,
				tile_size,
			}
			rl.DrawRectangleRec(rect, color)
		} 
	}

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

	rl.EndTextureMode()
	

	{ // DRAW TO WINDOW
		rl.BeginDrawing()
		defer rl.EndDrawing()

		rl.ClearBackground(rl.BLACK)



		screen_width := f32(rl.GetScreenWidth())
		screen_height := f32(rl.GetScreenHeight())

		scale := min(screen_width/f32(g.render_texture.texture.width), screen_height/f32(g.render_texture.texture.height))

		src := rl.Rectangle{ 0, 0, f32(g.render_texture.texture.width), f32(-g.render_texture.texture.height) }
		
		window_midpoint_x    := screen_width -  (f32(g.render_texture.texture.width)   * scale) / 2
		window_midpoint_y    := screen_height - (f32(g.render_texture.texture.height)  * scale) / 2
		window_scaled_width  := f32(g.render_texture.texture.width)  * scale
		window_scaled_height := f32(g.render_texture.texture.height) * scale

		dst := rl.Rectangle{(screen_width - window_scaled_width)/2, (screen_height - window_scaled_height)/2, window_scaled_width, window_scaled_height}
		rl.DrawTexturePro(g.render_texture.texture, src, dst, [2]f32{0,0}, 0, rl.WHITE)
		
		draw_debug_overlay()

	}
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

	g.render_texture = rl.LoadRenderTexture(1280, 720)	

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
