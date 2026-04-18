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

// Gameboy-style 4-color palette, light -> dark.
PALETTE_1 :: rl.Color{0xD0, 0xD0, 0x58, 0xFF}
PALETTE_2 :: rl.Color{0xA0, 0xA8, 0x40, 0xFF}
PALETTE_3 :: rl.Color{0x70, 0x80, 0x28, 0xFF}
PALETTE_4 :: rl.Color{0x40, 0x50, 0x10, 0xFF}

Direction :: enum {
	None,
	Up,
	Left,
	Down,
	Right
}

Moving_State :: enum {
	Idle,
	Moving
}

Tile_Type :: enum {
	Trail,
	Solid,
}

tile_size :: 64
chunk_width :: 5
chunk_height :: 5

tile_size_f : f32 : tile_size
chunk_width_f : f32 : chunk_width
chunk_height_f : f32 : chunk_height

tiles_in_chunk :: chunk_width * chunk_height


max_chunks :: 36
max_tiles :: tiles_in_chunk*max_chunks


Tilemap :: struct {
	tiles : [max_tiles]int,
	width : int,
	height : int,
	num_chunks_x : int,
	num_chunks_y : int,
}

Crab_Pos :: struct {
	chunk:   [2]int,   // which chunk the crab is in
	rel_pos: [2]f32,   // chunk-local position in tile units, [0, chunk_width) x [0, chunk_height). tile N center at rel_pos = N + 0.5.
}


Debug_State :: struct {
	show_overlay: bool,
	paused:       bool,
	player_speed: f32,
	debug_draw:   bool,
	force_reload_requested:  bool,
	force_restart_requested: bool,
}


zoom_timer_duration_sec : f32 = 0.25
camera_zoom_rearrange_mode : f32 = 0.4
selector_move_duration : f32 = 0.2


// Doesn't contain any "meta" state like
// inputs and debug state
Game_State :: struct {
	player_pos: rl.Vector2,      // derived each frame from crab pos; kept here for rendering/debug
	hovered_chunk : [2]int,
	is_chunk_selection_active : bool,
	selector_move_timer : f32,
	selected_chunk : [2]int,
	current_level : int,
	tilemap : Tilemap,
	move_state: Moving_State,
	move_speed: f32,
	current_direction: Direction,
	queued_direction: Direction,
	player_tile: [2]int,
	is_rearranging_chunks : bool,
	zoom_timer : f32,
	camera_zoom : f32,
	camera_target : [2]f32,
	crab: Crab_Pos,
	elapsed_time: f32,
}

level_cap :: 32 // just add more if there ends up being more
num_levels :: 10 // just add more if there ends up being more

play_sound_by_name :: proc(name : string) {
	m_sound := g.sfx_bank[name]
	rl.PlaySound(m_sound)
}

Game_Memory :: struct {
	sfx_bank : map[string]rl.Sound,
	render_texture : rl.RenderTexture2D,
	old_input_state : All_Input_State,
	input_state : All_Input_State,
	irs : Input_Recording_State,
	gs : Game_State,
	levels : [level_cap]Tilemap,
	run: bool,
	debug: Debug_State,
	crabby_texture: rl.Texture2D,
	coon_texture: rl.Texture2D,
	key_texture: rl.Texture2D,
	lock_texture: rl.Texture2D,
	flag_texture: rl.Texture2D,
	lcd_font: rl.Font,
	dmg_shader: rl.Shader,
	dmg_enabled: bool,
}

g: ^Game_Memory


game_camera :: proc() -> rl.Camera2D {
	// w := f32(rl.GetScreenWidth())
	// h := f32(rl.GetScreenHeight())

	w := f32(g.render_texture.texture.width)
	h := f32(g.render_texture.texture.height)

	return {
		zoom = g.gs.camera_zoom,
		// Fixed camera anchored at world origin so the player visibly moves on
		// screen. Change `target` to `g.gs.player_pos` for a follow-cam.
		target = g.gs.camera_target,
		offset = { w/2, h/2 },
	}
}




draw_debug_overlay :: proc() {
	if !g.debug.show_overlay do return

	panel := rl.Rectangle{8, 140, 280, 362}
	rl.GuiPanel(panel, "debug  [F3 hide  F4 pause]")

	px := panel.x
	py := panel.y + 28

	rl.DrawText(fmt.ctprintf("%d fps", rl.GetFPS()),                                   i32(px)+8, i32(py),    10, rl.BLACK)
	rl.DrawText(fmt.ctprintf("pos %.1f, %.1f", g.gs.player_pos.x, g.gs.player_pos.y), i32(px)+8, i32(py)+16, 10, rl.BLACK)
	if g.debug.paused {
		rl.DrawText("PAUSED", i32(px)+200, i32(py), 10, rl.MAROON)
	}

	rl.GuiSlider(
		{px+60, py+36, 120, 16},
		"speed",
		fmt.ctprintf("%.0f", g.debug.player_speed),
		&g.debug.player_speed,
		0, 400,
	)

	if rl.GuiButton({px+8, py+60, 120, 20}, "reset pos") {
		g.gs.player_pos = {}
	}
	rl.GuiCheckBox({px+136, py+62, 16, 16}, "draw debug", &g.debug.debug_draw)

	// Save / load
	if rl.GuiButton({px+8,   py+88, 120, 20}, "save (F10)") { t_save_data() }
	if rl.GuiButton({px+136, py+88, 120, 20}, "load (F11)") { t_load_data(context.temp_allocator) }

	// Hot reload / restart
	if rl.GuiButton({px+8,   py+114, 120, 20}, "hot reload (F5)") { g.debug.force_reload_requested  = true }
	if rl.GuiButton({px+136, py+114, 120, 20}, "restart (F6)")    { g.debug.force_restart_requested = true }

	// Rearrange mode — sync zoom timer when state flips.
	prev_rearrange := g.gs.is_rearranging_chunks
	rl.GuiCheckBox({px+8, py+144, 16, 16}, "rearrange (Z)", &g.gs.is_rearranging_chunks)
	if g.gs.is_rearranging_chunks != prev_rearrange {
		g.gs.zoom_timer = zoom_timer_duration_sec
	}

	// Record / playback — label tracks the triple state.
	rec_label : cstring = "record (L)"
	if g.irs.is_recording do rec_label = "stop recording (L)"
	if g.irs.is_playback  do rec_label = "stop playback (L)"
	if rl.GuiButton({px+8, py+170, 248, 20}, rec_label) {
		cycle_record_playback()
	}

	// Level slots 0-9.
	rl.DrawText(fmt.ctprintf("level %d", g.gs.current_level), i32(px)+8, i32(py)+200, 10, rl.BLACK)
	for i in 0..<10 {
		bx := px + 8 + f32(i) * 25
		if rl.GuiButton({bx, py+216, 23, 23}, fmt.ctprintf("%d", i)) {
			swap_to_level(i)
		}
	}

	rl.GuiCheckBox({px+8, py+250, 16, 16}, "DMG shader", &g.dmg_enabled)
}




@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "Cabin Jam 2026")
	rl.InitAudioDevice()
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(60)
	rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
	g = new(Game_Memory)

	g^ = Game_Memory {
		run = true,
		debug = { show_overlay = false, player_speed = 100 },
	}

	g.render_texture = rl.LoadRenderTexture(1280, 720)

	g.crabby_texture = rl.LoadTexture("assets/crab-still.png")
	g.key_texture = rl.LoadTexture("assets/key.png")
	g.lock_texture = rl.LoadTexture("assets/lock.png")
	g.flag_texture = rl.LoadTexture("assets/flag.png")
	g.coon_texture = rl.LoadTexture("assets/coon.png")

	g.lcd_font = rl.LoadFontEx("assets/fonts/LCD2B.TTF", 72, nil, 0)
	rl.SetTextureFilter(g.lcd_font.texture, .POINT)

	g.dmg_shader = rl.LoadShader(nil, "assets/shaders/gameboy_dmg.fs")
	g.dmg_enabled = true
	{
		grid_size     : f32 = 4
		grid_strength : f32 = 0.35
		palette_as_vec4 :: proc(c: rl.Color) -> rl.Vector4 {
			return {f32(c.r)/255.0, f32(c.g)/255.0, f32(c.b)/255.0, f32(c.a)/255.0}
		}
		p0 := palette_as_vec4(PALETTE_1)
		p1 := palette_as_vec4(PALETTE_2)
		p2 := palette_as_vec4(PALETTE_3)
		p3 := palette_as_vec4(PALETTE_4)

		rl.SetShaderValue(g.dmg_shader, rl.GetShaderLocation(g.dmg_shader, "gridSize"),     &grid_size,     .FLOAT)
		rl.SetShaderValue(g.dmg_shader, rl.GetShaderLocation(g.dmg_shader, "gridStrength"), &grid_strength, .FLOAT)
		rl.SetShaderValue(g.dmg_shader, rl.GetShaderLocation(g.dmg_shader, "palette0"), &p0, .VEC4)
		rl.SetShaderValue(g.dmg_shader, rl.GetShaderLocation(g.dmg_shader, "palette1"), &p1, .VEC4)
		rl.SetShaderValue(g.dmg_shader, rl.GetShaderLocation(g.dmg_shader, "palette2"), &p2, .VEC4)
		rl.SetShaderValue(g.dmg_shader, rl.GetShaderLocation(g.dmg_shader, "palette3"), &p3, .VEC4)
	}

	tilemap := init_tilemap_by_specifying_chunks(3, 2)

	g.gs.tilemap = tilemap

	g.gs.current_direction = .None
	g.gs.queued_direction  = .None
	g.gs.move_state        = .Idle
	g.gs.move_speed        = 4.0 // tiles per second
	g.gs.camera_zoom = 1.0

	spawn: for ty in 0..<g.gs.tilemap.height {
		for tx in 0..<g.gs.tilemap.width {
			if tilemap_is_walkable(&g.gs.tilemap, tx, ty) {
				g.gs.crab.chunk   = {tx / chunk_width, ty / chunk_height}
				g.gs.crab.rel_pos = {
					f32(tx %% chunk_width)  + 0.5,
					f32(ty %% chunk_height) + 0.5,
				}
				g.gs.player_pos = crab_world_pos(&g.gs.tilemap, g.gs.crab)
				break spawn
			}
		}
	}

	g.levels[1] = init_tilemap_by_specifying_chunks(4, 4)
	g.levels[2] = init_tilemap_by_specifying_chunks(2, 1)
	g.levels[3] = init_tilemap_by_specifying_chunks(3, 3)
	g.levels[4] = init_tilemap_by_specifying_chunks(2, 2)
	g.levels[5] = init_tilemap_by_specifying_chunks(5, 5)
	g.levels[6] = init_tilemap_by_specifying_chunks(4, 4)
	g.levels[7] = init_tilemap_by_specifying_chunks(4, 4)

	g.sfx_bank["smack"] = rl.LoadSound("assets/billiard-pool-hit.wav")
	g.sfx_bank["angel-choir"] = rl.LoadSound("assets/angel-choir.wav")
	g.sfx_bank["powder-impact"] = rl.LoadSound("assets/SFX_impactpunchbag01.wav")
	g.sfx_bank["woosh"] = rl.LoadSound("assets/SFX_EquipEquipmentOnev1.wav")
	g.sfx_bank["ui-move-1"] = rl.LoadSound("assets/SFX_Clickv1variation01.wav")
	g.sfx_bank["ui-move-2"] = rl.LoadSound("assets/SFX_SelectionEquipmentTwov1.wav")
	g.sfx_bank["confirm"] = rl.LoadSound("assets/Confirm.wav")
	g.sfx_bank["put-chunk"] = rl.LoadSound("assets/SFX_OptionChangev7.wav")

	t_load_data(context.temp_allocator)

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
	rl.UnloadFont(g.lcd_font)
	rl.UnloadShader(g.dmg_shader)
	rl.UnloadTexture(g.crabby_texture)
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
	if rl.IsKeyPressed(.F5) do return true
	if g.debug.force_reload_requested {
		g.debug.force_reload_requested = false
		return true
	}
	return false
}

@(export)
game_force_restart :: proc() -> bool {
	if rl.IsKeyPressed(.F6) do return true
	if g.debug.force_restart_requested {
		g.debug.force_restart_requested = false
		return true
	}
	return false
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}
