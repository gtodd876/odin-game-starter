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
import hm "core:container/handle_map"

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




Debug_State :: struct {
	show_overlay: bool,
	paused:       bool,
	player_speed: f32,
	debug_draw:   bool,
	force_reload_requested:  bool,
	force_restart_requested: bool,
}

Level :: struct {
	tilemap : Tilemap,
	crab_start_pos : Tilemap_Pos,
	raccoon_start_pool : [10]Raccoon,
}


crab_anim_fps : f32 : 24
crab_anim_frames :: 12

raccoon_anim_fps : f32 : 24
raccoon_anim_frames :: 18

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
	current_level_index : int,
	level : Level,
	move_state: Moving_State,
	prev_walking_gameplay: bool,
	move_speed: f32,
	current_direction: Direction,
	queued_direction: Direction,
	player_tile: [2]int,
	is_rearranging_chunks : bool,
	zoom_timer : f32,
	swap_selection_change_timer : f32,
	camera_zoom : f32,
	camera_target : [2]f32,
	crab: Tilemap_Pos,
	num_keys_crab_has : int,
	crab_anim_time: f32,
	crab_facing: Direction,
	elapsed_time: f32,
	raccoon_pool : [10]Raccoon,
	raccoon_spawn_delay : f32,
	game_over: bool,
	level_complete: bool,
}

raccoon_spawn_delay_duration : f32 : 4.0

raccoon_level_index :: 4

level_cap :: 32 // just add more if there ends up being more
num_levels :: 10 // just add more if there ends up being more

play_sound_by_name :: proc(name : string) {
	m_sound := g.sfx_bank[name]
	rl.PlaySound(m_sound)
}

Raccoon :: struct {
	active : bool,
	pos : Tilemap_Pos,
	direction : Direction,
}

Game_Memory :: struct {
	sfx_bank : map[string]rl.Sound,
	drone_music     : rl.Music,
	clickies_music  : rl.Music,
	dingdings_music : rl.Music,
	render_texture : rl.RenderTexture2D,
	old_input_state : All_Input_State,
	input_state : All_Input_State,
	irs : Input_Recording_State,
	gs : Game_State,
	// this level is the one used for setting an initial state
	// the one in gs above will change when player is playing
	initial_current_level : Level,
	levels : [level_cap]Level,
	run: bool,
	debug: Debug_State,
	editor_selected_tile_type : Tile_Type,
	crabby_texture: rl.Texture2D,
	crab_walk_textures: [12]rl.Texture2D,
	raccoon_walk_textures: [raccoon_anim_frames]rl.Texture2D,
	key_texture: rl.Texture2D,
	lock_texture: rl.Texture2D,
	flag_texture: rl.Texture2D,
	move_crab_sticker_texture : rl.Texture2D,
	a_button_panel_texture : rl.Texture2D,
	right_bumper_hold_panel_texture : rl.Texture2D,
	right_bumper_release_panel_texture : rl.Texture2D,
	a_button_select_texture : rl.Texture2D,
	a_button_swap_texture : rl.Texture2D,
	dpad_move_selection_texture : rl.Texture2D,
	dpad_crab_walk_texture : rl.Texture2D,
	danger_texture : rl.Texture2D,
	lcd_font: rl.Font,
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
	rl.DrawText(fmt.ctprintf("level %d", g.gs.current_level_index), i32(px)+8, i32(py)+200, 10, rl.BLACK)
	for i in 0..<10 {
		bx := px + 8 + f32(i) * 25
		if rl.GuiButton({bx, py+216, 23, 23}, fmt.ctprintf("%d", i)) {
			swap_to_level(i)
		}
	}
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
	for i in 0..<12 {
		g.crab_walk_textures[i] = rl.LoadTexture(fmt.ctprintf("assets/crab-%d.png", i + 1))
	}
	g.key_texture = rl.LoadTexture("assets/key.png")
	g.lock_texture = rl.LoadTexture("assets/lock-borderless.png")
	g.flag_texture = rl.LoadTexture("assets/flag-borderless.png")
	for i in 0..<raccoon_anim_frames {
		g.raccoon_walk_textures[i] = rl.LoadTexture(fmt.ctprintf("assets/raccoon-%d.png", i + 1))
	}
	g.move_crab_sticker_texture = rl.LoadTexture("assets/move_crab_sticker.png")
	g.a_button_panel_texture = rl.LoadTexture("assets/a_button_panel.png")
	g.right_bumper_hold_panel_texture = rl.LoadTexture("assets/right_bumper_hold_panel.png")
	g.right_bumper_release_panel_texture = rl.LoadTexture("assets/right_bumper_release_panel.png")

	g.a_button_select_texture = rl.LoadTexture("assets/a_button_select.png")
	g.a_button_swap_texture = rl.LoadTexture("assets/a_button_swap.png")
	g.dpad_move_selection_texture = rl.LoadTexture("assets/dpad_move_selection.png")
	g.dpad_crab_walk_texture = rl.LoadTexture("assets/dpad_crab_walk.png")
	g.danger_texture = rl.LoadTexture("assets/danger.png")

	g.lcd_font = rl.LoadFontEx("assets/fonts/LCD2B.TTF", 72, nil, 0)
	rl.SetTextureFilter(g.lcd_font.texture, .POINT)

	g.gs.current_direction = .None
	g.gs.queued_direction  = .None
	g.gs.crab_facing       = .Down
	g.gs.move_state        = .Idle
	g.gs.move_speed        = 4.0 // tiles per second
	g.gs.camera_zoom = 1.0

	spawn: for ty in 0..<g.gs.level.tilemap.height {
		for tx in 0..<g.gs.level.tilemap.width {
			if tilemap_is_walkable(&g.gs.level.tilemap, tx, ty) {
				g.gs.crab.chunk   = {tx / chunk_width, ty / chunk_height}
				g.gs.crab.rel_pos = {
					f32(tx %% chunk_width)  + 0.5,
					f32(ty %% chunk_height) + 0.5,
				}
				g.gs.player_pos = tilemap_pos_to_world_pos(&g.gs.level.tilemap, g.gs.crab)
				break spawn
			}
		}
	}

	// g.levels[0].tilemap = init_tilemap_by_specifying_chunks(1, 1)
	// g.levels[1].tilemap = init_tilemap_by_specifying_chunks(2, 1)
	// g.levels[2].tilemap = init_tilemap_by_specifying_chunks(2, 2)
	// g.levels[3].tilemap = init_tilemap_by_specifying_chunks(3, 3)
	// g.levels[4].tilemap = init_tilemap_by_specifying_chunks(3, 3)
	// g.levels[5].tilemap = init_tilemap_by_specifying_chunks(4, 4)
	// g.levels[6].tilemap = init_tilemap_by_specifying_chunks(4, 4)
	// g.levels[7].tilemap = init_tilemap_by_specifying_chunks(4, 4)
	// g.levels[8].tilemap = init_tilemap_by_specifying_chunks(5, 5)
	// g.levels[9].tilemap = init_tilemap_by_specifying_chunks(5, 5)


	g.sfx_bank["smack"]     = rl.LoadSound("assets/billiard-pool-hit.ogg")
	g.sfx_bank["ui-move-1"] = rl.LoadSound("assets/SFX_Clickv1variation01.ogg")
	g.sfx_bank["put-chunk"] = rl.LoadSound("assets/SFX_OptionChangev7.ogg")
	g.sfx_bank["zoom-out"]  = rl.LoadSound("assets/zoom-in.ogg")
	g.sfx_bank["zoom-in"]   = rl.LoadSound("assets/SFX_EquipEquipmentOnev1.ogg")
	g.sfx_bank["win"]       = rl.LoadSound("assets/complete.ogg")
	g.sfx_bank["cluster"]   = rl.LoadSound("assets/cluster.ogg")
	g.sfx_bank["chime"]     = rl.LoadSound("assets/chime.ogg")
	g.sfx_bank["unlock"]    = rl.LoadSound("assets/lock.ogg")

	g.drone_music     = rl.LoadMusicStream("assets/drone-2.ogg")
	g.clickies_music  = rl.LoadMusicStream("assets/clickies.ogg")
	g.dingdings_music = rl.LoadMusicStream("assets/dingdings.mp3")
	g.drone_music.looping     = true
	g.clickies_music.looping  = true
	g.dingdings_music.looping = true

	rl.PlayMusicStream(g.drone_music)
	rl.PlayMusicStream(g.clickies_music)
	rl.PauseMusicStream(g.clickies_music)
	rl.PlayMusicStream(g.dingdings_music)
	rl.PauseMusicStream(g.dingdings_music)  // held paused at position 0 until first rearrange

	t_load_data(context.temp_allocator)

	g.initial_current_level = g.levels[g.gs.current_level_index]
	g.gs.level = g.levels[g.gs.current_level_index]

	swap_to_level(0)

	// g.levels[2].tilemap = init_tilemap_by_specifying_chunks(2, 1)
	// tmp := g.levels[6]
	// g.levels[6] = g.levels[7]
	// g.levels[7] = tmp
	
	g.levels[9] = {}
	g.levels[9].tilemap = init_tilemap_by_specifying_chunks(5, 5)
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
	rl.UnloadTexture(g.crabby_texture)
	for i in 0..<crab_anim_frames {
		rl.UnloadTexture(g.crab_walk_textures[i])
	}
	for i in 0..<raccoon_anim_frames {
		rl.UnloadTexture(g.raccoon_walk_textures[i])
	}
	for _, sound in g.sfx_bank {
		rl.UnloadSound(sound)
	}
	rl.UnloadMusicStream(g.drone_music)
	rl.UnloadMusicStream(g.clickies_music)
	rl.UnloadMusicStream(g.dingdings_music)
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
