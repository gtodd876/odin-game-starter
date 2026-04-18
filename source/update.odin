package game

// NOTE(johnb) only reason putting in here is i found i often
// want to just see update stuff in one pane,
// and anything else in the other pane at the same time

import rl "vendor:raylib"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:os"
import "core:math/linalg"

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

	// if rl.IsKeyPressed(.F12) {
	// 	intrinsics.debug_trap()
	// }
	update()


	// Everything on tracking allocator is valid until end-of-frame.
	free_all(context.temp_allocator)
}

tilemap_is_coord_in_bounds :: proc(tilemap : ^Tilemap, x, y : int) -> bool {
	in_bounds := x >= 0 && x < tilemap.width &&
		y >= 0 && y < tilemap.height
	return in_bounds
}

tilemap_set_tile :: proc(tilemap : ^Tilemap, x, y, val : int) {
	in_bounds := tilemap_is_coord_in_bounds(tilemap, x, y)

	if in_bounds {
		tilemap.tiles[(y*tilemap.width)+x] = val
	} else {
		// Why are u here?
		when ODIN_DEBUG {
			intrinsics.debug_trap()
		}
	}
}

tilemap_get_tile_val ::proc(tilemap :^Tilemap, x, y : int) -> int {
	in_bounds := tilemap_is_coord_in_bounds(tilemap, x, y)
	val := 0
	if in_bounds {
		val = tilemap.tiles[(y*tilemap.width)+x]
	} else {
	}
	return val
}

set_chunk_tiles_in_tilemap :: proc(tilemap : ^Tilemap, chunk_x, chunk_y : int, tiles:[]int) {
	min_tile_x := chunk_x * chunk_width
	min_tile_y := chunk_y * chunk_height
	max_tile_x := min_tile_x + chunk_width
	max_tile_y := min_tile_y + chunk_height

	for tile_x, i_x in min_tile_x..<max_tile_x {
		for tile_y, i_y in min_tile_y..<max_tile_y {
			tile_val := tiles[(i_y*chunk_width)+i_x]
			tilemap_set_tile(tilemap, tile_x, tile_y, tile_val)
		}
	}

}

init_tilemap_by_specifying_chunks :: proc(num_chunks_x, num_chunks_y : int) -> Tilemap {
	tilemap := Tilemap {
		width = num_chunks_x * chunk_width,
		height = num_chunks_y * chunk_height,
		num_chunks_x = num_chunks_x,
		num_chunks_y = num_chunks_y
	}
	return tilemap
}

tilemap_get_chunk_tiles ::proc(tilemap : ^Tilemap, chunk_x, chunk_y : int) -> [tiles_in_chunk]int {
	tilemap_chunk := [tiles_in_chunk]int{}
	min_tile_x := chunk_x * chunk_width
	min_tile_y := chunk_y * chunk_height
	max_tile_x := min_tile_x + chunk_width
	max_tile_y := min_tile_y + chunk_height

	for tile_x, i_x in min_tile_x..<max_tile_x {
		for tile_y, i_y in min_tile_y..<max_tile_y {
			tile_val := tilemap.tiles[(tile_y*tilemap.width)+tile_x]
			tilemap_chunk[(i_y*chunk_width)+i_x] = tile_val
		}
	}
	return tilemap_chunk
}

data_file_filename :: "data"

t_load_data :: proc(allocator : runtime.Allocator = context.allocator) -> bool {
	s : Serializer
	data, rerr := os.read_entire_file_from_path(data_file_filename, allocator)
	if rerr != nil {
		fmt.printfln("error reading from data file")
		return false
	}
	serializer_init_reader(&s, data[:])
	ok := serialize(&s, &g.gs.tilemap)
	if !ok  {
		fmt.printfln("error serializing reader")
		return false
	}

	
	return true
}


tilemap_world_origin :: proc(t: ^Tilemap) -> [2]f32 {
	return {
		-f32(t.width)  * tile_size_f * 0.5,
		-f32(t.height) * tile_size_f * 0.5,
	}
}

tile_center_world :: proc(t: ^Tilemap, tx, ty: int) -> [2]f32 {
	o := tilemap_world_origin(t)
	return {
		o.x + f32(tx)*tile_size_f + tile_size_f*0.5,
		o.y + f32(ty)*tile_size_f + tile_size_f*0.5,
	}
}

tilemap_is_walkable :: proc(t: ^Tilemap, tx, ty: int) -> bool {
	if tx < 0 || tx >= t.width || ty < 0 || ty >= t.height do return false
	return Tile_Type(t.tiles[ty*t.width + tx]) == .Trail
}

direction_vector :: proc(d: Direction) -> [2]int {
	switch d {
	case .Up:    return { 0, -1}
	case .Down:  return { 0,  1}
	case .Left:  return {-1,  0}
	case .Right: return { 1,  0}
	case .None:  return { 0,  0}
	}
	return {0, 0}
}

opposite_direction :: proc(d: Direction) -> Direction {
	switch d {
	case .Up:    return .Down
	case .Down:  return .Up
	case .Left:  return .Right
	case .Right: return .Left
	case .None:  return .None
	}
	return .None
}

chunk_world_origin :: proc(t: ^Tilemap, chunk_x, chunk_y: int) -> [2]f32 {
	o := tilemap_world_origin(t)
	return {
		o.x + f32(chunk_x) * chunk_width_f  * tile_size_f,
		o.y + f32(chunk_y) * chunk_height_f * tile_size_f,
	}
}

crab_world_pos :: proc(t: ^Tilemap, cp: Crab_Pos) -> [2]f32 {
	co := chunk_world_origin(t, cp.chunk.x, cp.chunk.y)
	return {
		co.x + cp.rel_pos.x * tile_size_f,
		co.y + cp.rel_pos.y * tile_size_f,
	}
}

crab_absolute_tile :: proc(cp: Crab_Pos) -> [2]int {
	return {
		cp.chunk.x * chunk_width  + int(cp.rel_pos.x),
		cp.chunk.y * chunk_height + int(cp.rel_pos.y),
	}
}

// Wrap rel_pos into [0, chunk_w) x [0, chunk_h), shifting chunk to compensate.
crab_normalize_chunk :: proc(cp: ^Crab_Pos) {
	for cp.rel_pos.x >= chunk_width_f  { cp.chunk.x += 1; cp.rel_pos.x -= chunk_width_f  }
	for cp.rel_pos.x < 0               { cp.chunk.x -= 1; cp.rel_pos.x += chunk_width_f  }
	for cp.rel_pos.y >= chunk_height_f { cp.chunk.y += 1; cp.rel_pos.y -= chunk_height_f }
	for cp.rel_pos.y < 0               { cp.chunk.y -= 1; cp.rel_pos.y += chunk_height_f }
}

crab_can_step :: proc(t: ^Tilemap, cp: Crab_Pos, dir: Direction) -> bool {
	if dir == .None do return false
	step := direction_vector(dir)
	probe_chunk := cp.chunk
	probe_local_x := int(cp.rel_pos.x) + step.x
	probe_local_y := int(cp.rel_pos.y) + step.y
	if probe_local_x < 0             { probe_chunk.x -= 1; probe_local_x += chunk_width  }
	if probe_local_x >= chunk_width  { probe_chunk.x += 1; probe_local_x -= chunk_width  }
	if probe_local_y < 0             { probe_chunk.y -= 1; probe_local_y += chunk_height }
	if probe_local_y >= chunk_height { probe_chunk.y += 1; probe_local_y -= chunk_height }
	abs_x := probe_chunk.x * chunk_width  + probe_local_x
	abs_y := probe_chunk.y * chunk_height + probe_local_y
	return tilemap_is_walkable(t, abs_x, abs_y)
}

update_crab :: proc() {
	gs := &g.gs
	t  := &gs.tilemap

	// Refresh derived state on the way out: wrap rel_pos/chunk, then world pos.
	defer {
		crab_normalize_chunk(&gs.crab)
		gs.player_pos = crab_world_pos(t, gs.crab)
	}

	// 1. Latest WASD press sets queued direction.
	if !g.gs.is_rearranging_chunks {
		if      IsKeyDown(.W) || IsKeyDown(.UP) do gs.queued_direction = .Up
		else if IsKeyDown(.S) || IsKeyDown(.DOWN) do gs.queued_direction = .Down
		else if IsKeyDown(.A) || IsKeyDown(.LEFT) do gs.queued_direction = .Left
		else if IsKeyDown(.D) || IsKeyDown(.RIGHT) do gs.queued_direction = .Right
	}
		

	// 2. Reversal is allowed mid-tile.
	if gs.move_state == .Moving &&
	   gs.queued_direction != .None &&
	   gs.queued_direction == opposite_direction(gs.current_direction) {
		gs.current_direction = gs.queued_direction
		gs.queued_direction = .None
	}

	// 3. Kick off from idle when queued leads into a walkable neighbor.
	if gs.move_state == .Idle && gs.queued_direction != .None {
		if crab_can_step(t, gs.crab, gs.queued_direction) {
			gs.current_direction = gs.queued_direction
			gs.move_state = .Moving
		}
		gs.queued_direction = .None
	}

	if gs.move_state != .Moving do return

	// 4. Advance rel_pos (tile units; move_speed is tiles/second).
	dv := direction_vector(gs.current_direction)
	dv_f := [2]f32{f32(dv.x), f32(dv.y)}
	pre_rel := gs.crab.rel_pos
	move_speed := gs.move_speed
	if g.gs.is_rearranging_chunks {
		move_speed *= 0.1
	}
	gs.crab.rel_pos += dv_f * move_speed * rl.GetFrameTime()

	// 5. Detect tile-center crossing. Tile centers sit at half-integers;
	// shift by -0.5 so they sit at integers, and a crossing is a change in
	// floor(rel - 0.5) along the motion axis.
	crossed_cx := gs.crab.rel_pos.x
	crossed_cy := gs.crab.rel_pos.y
	crossed := false

	if dv.x != 0 {
		pre_u  := math.floor(pre_rel.x - 0.5)
		post_u := math.floor(gs.crab.rel_pos.x - 0.5)
		if pre_u != post_u {
			crossed = true
			u_cross := dv.x > 0 ? post_u : pre_u
			crossed_cx = u_cross + 0.5
		}
	}
	if dv.y != 0 {
		pre_u  := math.floor(pre_rel.y - 0.5)
		post_u := math.floor(gs.crab.rel_pos.y - 0.5)
		if pre_u != post_u {
			crossed = true
			u_cross := dv.y > 0 ? post_u : pre_u
			crossed_cy = u_cross + 0.5
		}
	}

	if !crossed do return

	// Just crossed a tile center. Temporarily snap rel_pos to the crossed center
	// so walkability probes evaluate from there; then decide turn / continue / stop.
	saved_rel   := gs.crab.rel_pos
	saved_chunk := gs.crab.chunk
	gs.crab.rel_pos = {crossed_cx, crossed_cy}
	crab_normalize_chunk(&gs.crab)

	turned := false
	if gs.queued_direction != .None && gs.queued_direction != gs.current_direction {
		if crab_can_step(t, gs.crab, gs.queued_direction) {
			gs.current_direction = gs.queued_direction
			turned = true
		}
	}
	gs.queued_direction = .None

	if !turned {
		if !crab_can_step(t, gs.crab, gs.current_direction) {
			// Stop at the crossed center.
			gs.current_direction = .None
			gs.move_state = .Idle
		} else {
			// Continue straight: restore the pre-normalize overshoot.
			gs.crab.rel_pos = saved_rel
			gs.crab.chunk = saved_chunk
		}
	}
}

update :: proc() {

	// NOTE(john): these are ints in here only because its easy to write in code
	// These are planned to be enum values once
	//... if we have an actual editor where we are placing these things

	tilemap := &g.gs.tilemap

	if rl.IsKeyPressed(.F3) do g.debug.show_overlay = !g.debug.show_overlay
	if rl.IsKeyPressed(.F4) do g.debug.paused = !g.debug.paused

	if rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}

	save_button := rl.KeyboardKey.F10
	if rl.IsKeyPressed(save_button) {
		s : Serializer
		serializer_init_writer(&s, allocator = context.temp_allocator)
		ok := serialize(&s, &g.gs.tilemap)
		werr := os.write_entire_file(data_file_filename, s.data[:])
		if werr != nil {
			fmt.printfln("error writing file to data file")
		}
		// else if werr == nil && ok {
		// 	save_message_timer = save_message_duration_sec
		// }
	}

	{ // swap levels
		level_keys := [?] rl.KeyboardKey {
			rl.KeyboardKey.ZERO,
			rl.KeyboardKey.ONE,
			rl.KeyboardKey.TWO,
			rl.KeyboardKey.THREE,
			rl.KeyboardKey.FOUR,
			rl.KeyboardKey.FIVE,
			rl.KeyboardKey.SIX,
			rl.KeyboardKey.SEVEN,
			rl.KeyboardKey.EIGHT,
			rl.KeyboardKey.NINE,
		}

		// save the active one to the levels
		g.levels[g.gs.current_level] = g.gs.tilemap

		for level_key, i in level_keys {
			if rl.IsKeyPressed(level_key) {
				g.gs.tilemap = g.levels[i]
				g.gs.current_level = i
			}
		}
	}

	load_button := rl.KeyboardKey.F11
	if rl.IsKeyPressed(load_button) {
		t_load_data(context.temp_allocator)
	}

	if g.debug.paused do return

	{ // editor stuff
		mouse_screen := rl.GetMousePosition()
		mouse_world := rl.GetScreenToWorld2D(mouse_screen, game_camera())
		mouse_rel_tilemap := mouse_world - tilemap_world_origin(tilemap)
		tile_x := int(mouse_rel_tilemap.x) / tile_size
		tile_y := int(mouse_rel_tilemap.y) / tile_size	
		if (rl.IsMouseButtonDown(.LEFT)) {
			tilemap_set_tile(tilemap, tile_x, tile_y, 1)
		} else if rl.IsMouseButtonDown(.RIGHT) {
			tilemap_set_tile(tilemap, tile_x, tile_y, 0)	
		}
	}

	{
		enter_rearrange_mode_key := rl.KeyboardKey.Z
		if IsKeyPressed(enter_rearrange_mode_key) {
			g.gs.is_rearranging_chunks = !g.gs.is_rearranging_chunks 
			g.gs.zoom_timer = zoom_timer_duration_sec
		}

		crab_wpos : = crab_world_pos(tilemap, g.gs.crab)


		if g.gs.zoom_timer > 0 {
			g.gs.zoom_timer -= rl.GetFrameTime()
			if g.gs.zoom_timer < 0 do g.gs.zoom_timer = 0
			p := 1.0 - ((g.gs.zoom_timer / zoom_timer_duration_sec)*(g.gs.zoom_timer / zoom_timer_duration_sec))*(g.gs.zoom_timer / zoom_timer_duration_sec)
			if g.gs.is_rearranging_chunks {
				g.gs.camera_target = linalg.lerp(crab_wpos, [2]f32{0,0}, p)
				g.gs.camera_zoom = linalg.lerp(f32(1.0), camera_zoom_rearrange_mode, p)
			} else {
				g.gs.camera_target = linalg.lerp([2]f32{0,0}, crab_wpos, p)
				g.gs.camera_zoom = linalg.lerp(camera_zoom_rearrange_mode, f32(1.0), p)
			}
		} else {
			if g.gs.is_rearranging_chunks {
				g.gs.camera_target = {}
			} else {
				g.gs.camera_target = crab_wpos
			}
		}
	}

	if g.gs.is_rearranging_chunks {
		if IsKeyPressed(.UP)    {
			play_sound_by_name("ui-move-1")
			g.gs.hovered_chunk.y -= 1
		}
		if IsKeyPressed(.DOWN)  {
			play_sound_by_name("ui-move-1")

			g.gs.hovered_chunk.y += 1
		}
		if IsKeyPressed(.LEFT)  {
			play_sound_by_name("ui-move-1")
			
			g.gs.hovered_chunk.x -= 1
		}
		if IsKeyPressed(.RIGHT) {
			play_sound_by_name("ui-move-1")
			
			g.gs.hovered_chunk.x += 1
		}

		if IsKeyPressed(.SPACE) {
			if g.gs.is_chunk_selection_active {
				play_sound_by_name("smack")
				hovered_tiles := tilemap_get_chunk_tiles(tilemap,
					g.gs.hovered_chunk.x, g.gs.hovered_chunk.y)
				selected_tiles := tilemap_get_chunk_tiles(tilemap,
					g.gs.selected_chunk.x, g.gs.selected_chunk.y)

				set_chunk_tiles_in_tilemap(tilemap, g.gs.hovered_chunk.x, g.gs.hovered_chunk.y, selected_tiles[:])
				set_chunk_tiles_in_tilemap(tilemap, g.gs.selected_chunk.x, g.gs.selected_chunk.y, hovered_tiles[:])

				// Crab rides along with whichever chunk was swapped out from under it.
				if g.gs.crab.chunk == g.gs.hovered_chunk {
					g.gs.crab.chunk = g.gs.selected_chunk
				} else if g.gs.crab.chunk == g.gs.selected_chunk {
					g.gs.crab.chunk = g.gs.hovered_chunk
				}
				g.gs.player_pos = crab_world_pos(tilemap, g.gs.crab)

				g.gs.is_chunk_selection_active = false
			} else {
				play_sound_by_name("put-chunk")
				g.gs.is_chunk_selection_active = true
				g.gs.selected_chunk = g.gs.hovered_chunk
			}
		}

	}


	// NOTE(john) make sure selection stays within the bounds
	// of the overall chunk arrangemetn
	//
	// Also if there are empty tilemaps with 0 dimensions
	// this will crash
	g.gs.hovered_chunk.x %%= tilemap.num_chunks_x
	g.gs.hovered_chunk.y %%= tilemap.num_chunks_y



	update_crab()


	rl.BeginTextureMode(g.render_texture)
	rl.ClearBackground(PALETTE_1)

	rl.BeginMode2D(game_camera())


	// NOTE(john) cause camera got centered at 0,0

	for chunk_x in 0..<tilemap.num_chunks_x {
		for chunk_y in 0..<tilemap.num_chunks_y {
			tilemap_chunk := tilemap_get_chunk_tiles(tilemap, chunk_x, chunk_y)
			origin := tilemap_world_origin(tilemap)
			chunk_pos := [2]f32{
    			origin.x + (tile_size_f*chunk_width_f*f32(chunk_x)),
       			origin.y + (tile_size_f*chunk_width_f*f32(chunk_y)),
			}

			// NOTE(johnb) units means pixels. Using the term units, cause
			// when camera
			// zooms out or in, suddenly its no longer measured in pixels,
			// so it made sense to me. But im fine with whatever terms
			chunk_width_in_units := tile_size_f*chunk_width_f
			chunk_height_in_units := tile_size_f*chunk_width_f

			for tile_x in 0..<chunk_width {
				for tile_y in 0..<chunk_height {
					i := tile_y*chunk_width + tile_x
					tile_type := tilemap_chunk[i]
					color := Tile_Type(tile_type) == .Solid ? PALETTE_4 : PALETTE_1
					rect := rl.Rectangle {
						chunk_pos.x + (tile_size*f32(tile_x)),
						chunk_pos.y + (tile_size*f32(tile_y)),
						tile_size,
						tile_size,
					}
					rl.DrawRectangleRec(rect, color)
				}
			}

			chunk_rect := rl.Rectangle {
				chunk_pos.x, chunk_pos.y, chunk_width_in_units, chunk_height_in_units
			}
			color := rl.YELLOW
			color.a = g.gs.is_rearranging_chunks ? 100 : 10

			// Note(john) using term chunk id to refer to the 2D index
			// which can really be thought of as an integer coordinate
			// system
			chunk_id := [2]int{chunk_x, chunk_y}
			if chunk_id == g.gs.hovered_chunk {
				color.a = 255
			} else if g.gs.is_chunk_selection_active {
				if chunk_id == g.gs.selected_chunk  {
					color = rl.WHITE
				}
			}

			rl.DrawRectangleLinesEx(chunk_rect, 4, color)
		}
	}

	chunk_pos := [2]f32 {0, 0}


	{ // DRAW CRAB
		tex := g.crabby_texture
		src := rl.Rectangle{0, 0, f32(tex.width), f32(tex.height)}
		dst := rl.Rectangle{g.gs.player_pos.x, g.gs.player_pos.y, tile_size_f, tile_size_f}
		origin := [2]f32{tile_size_f * 0.5, tile_size_f * 0.5}
		rl.DrawTexturePro(tex, src, dst, origin, 0, rl.WHITE)
	}

	if g.debug.debug_draw {
		rl.DrawRectangleLinesEx({g.gs.player_pos.x - 8, g.gs.player_pos.y - 8, 16, 16}, 1, rl.MAGENTA)
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

		// draw_debug_overlay()

	}
}