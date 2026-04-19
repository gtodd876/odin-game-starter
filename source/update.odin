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
		cycle_record_playback()
	}

	update_all_input_state()

	if g.irs.is_playback {
		playback_input(&g.irs, &g.gs, &g.input_state)
	} else if g.irs.is_recording {
		record_input(&g.irs, &g.input_state)
	}

	g.old_input_state = g.input_state

	rl.UpdateMusicStream(g.drone_music)
	rl.UpdateMusicStream(g.clickies_music)
	rl.UpdateMusicStream(g.dingdings_music)

	// if rl.IsKeyPressed(.F12) {
	// 	intrinsics.debug_trap()
	// }
	update()


	// Everything on tracking allocator is valid until end-of-frame.
	free_all(context.temp_allocator)
}


data_file_filename :: "data"

t_save_data :: proc() {

	g.gs.level.crab_start_pos = g.gs.crab
	g.levels[g.gs.current_level_index] = g.gs.level
	g.initial_current_level = g.gs.level

	s : Serializer
	serializer_init_writer(&s, allocator = context.temp_allocator)
	serialize(&s, &g.levels)
	werr := os.write_entire_file(data_file_filename, s.data[:])
	if werr != nil {
		fmt.printfln("error writing file to data file")
	}
}

t_load_data :: proc(allocator : runtime.Allocator = context.allocator) -> bool {
	if os.exists(data_file_filename) {
		s : Serializer
		data, rerr := os.read_entire_file_from_path(data_file_filename, allocator)
		if rerr != nil {
			fmt.printfln("error reading from data file")
			return false
		}
		serializer_init_reader(&s, data[:])
		ok := serialize(&s, &g.levels)
		if !ok  {
			fmt.printfln("error serializing reader")
			return false
		}
	}

	return true
}

// Centered modal popup using the HUD's rounded-rect style.
// Caller passes screen-center-aligned text lines; pass "" for middle to collapse to 2 lines.
draw_popup :: proc(heading, middle, footer: cstring) {
	rt_w := f32(g.render_texture.texture.width)
	rt_h := f32(g.render_texture.texture.height)

	popup_w := rt_w * 0.55
	popup_h := rt_h * 0.45
	popup_x := (rt_w - popup_w) * 0.5
	popup_y := (rt_h - popup_h) * 0.5

	popup_rect := rl.Rectangle{popup_x, popup_y, popup_w, popup_h}
	rl.DrawRectangleRounded       (popup_rect, 0.15, 8,    PALETTE_1)
	rl.DrawRectangleRoundedLinesEx(popup_rect, 0.15, 8, 4, PALETTE_4)

	heading_size : f32 = 72
	middle_size  : f32 = 64
	footer_size  : f32 = 32
	spacing      : f32 = 2
	gap          : f32 = 24

	has_middle := len(string(middle)) > 0

	h_dim := rl.MeasureTextEx(g.lcd_font, heading, heading_size, spacing)
	m_dim : [2]f32
	if has_middle do m_dim = rl.MeasureTextEx(g.lcd_font, middle, middle_size, spacing)
	f_dim := rl.MeasureTextEx(g.lcd_font, footer,  footer_size,  spacing)

	total_h := h_dim.y + gap + f_dim.y
	if has_middle do total_h += m_dim.y + gap

	center_x := popup_x + popup_w * 0.5
	y := popup_y + (popup_h - total_h) * 0.5

	rl.DrawTextEx(g.lcd_font, heading, {center_x - h_dim.x * 0.5, y}, heading_size, spacing, PALETTE_4)
	y += h_dim.y + gap

	if has_middle {
		rl.DrawTextEx(g.lcd_font, middle, {center_x - m_dim.x * 0.5, y}, middle_size, spacing, PALETTE_4)
		y += m_dim.y + gap
	}

	rl.DrawTextEx(g.lcd_font, footer, {center_x - f_dim.x * 0.5, y}, footer_size, spacing, PALETTE_4)
}

swap_to_level :: proc(i: int) {
	g.gs.current_level_index = i
	g.initial_current_level = g.levels[i]
	g.gs.level = g.initial_current_level
	g.gs.crab = g.initial_current_level.crab_start_pos

	g.gs.raccoon_active = (i == raccoon_level_index)
	if g.gs.raccoon_active {
		spawn_raccoon_opposite_crab()
	}

	g.gs.game_over      = false
	g.gs.level_complete = false

	rl.ResumeMusicStream(g.drone_music)

	// g.initial_current_level
	// g.levels[g.gs.current_level_index] = g.initial_current_level
	// g.gs.level = g.levels[i]
	// g.gs.crab = g.gs.level.crab_start_pos

	g.gs.num_keys_crab_has = 0
}

spawn_raccoon_opposite_crab :: proc() {
	t := &g.gs.level.tilemap
	crab_tile := tilemap_pos_absolute_tile(g.gs.crab)
	target_x := t.width  - 1 - crab_tile.x
	target_y := t.height - 1 - crab_tile.y

	// Spiral outward from the opposite corner until we land on a walkable tile.
	// Guaranteed to terminate because the crab's own tile is walkable.
	max_radius := t.width + t.height
	found_x, found_y := target_x, target_y
	search: for radius in 0..=max_radius {
		for dy in -radius..=radius {
			for dx in -radius..=radius {
				if abs(dx) != radius && abs(dy) != radius do continue
				tx := target_x + dx
				ty := target_y + dy
				if tx < 0 || tx >= t.width || ty < 0 || ty >= t.height do continue
				if tx == crab_tile.x && ty == crab_tile.y do continue
				if tilemap_is_walkable(t, tx, ty) {
					found_x = tx
					found_y = ty
					break search
				}
			}
		}
	}

	g.gs.raccoon = absolute_tile_to_tilemap_pos(found_x, found_y)
	g.gs.raccoon_direction = .None
	g.gs.raccoon_move_speed = 3.0
}





cycle_record_playback :: proc() {
	if g.irs.is_playback {
		end_input_playback(&g.irs)
		g.old_input_state = {}
	} else if g.irs.is_recording {
		end_recording_input(&g.irs)
		begin_input_playback(&g.irs, &g.gs)
		g.irs.playback_frame = 0
	} else {
		begin_recording_input(&g.irs, &g.gs)
	}
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


crab_can_step :: proc(t: ^Tilemap, cp: Tilemap_Pos, dir: Direction) -> bool {
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
	if g.gs.game_over || g.gs.level_complete do return
	gs := &g.gs
	t  := &gs.level.tilemap

	// Refresh derived state on the way out: wrap rel_pos/chunk, then world pos.
	defer {
		tilemap_pos_normalize_chunk(&gs.crab)
		gs.player_pos = tilemap_pos_to_world_pos(t, gs.crab)
		if gs.move_state == .Moving {
			gs.crab_anim_time += rl.GetFrameTime()
			if gs.current_direction != .None {
				gs.crab_facing = gs.current_direction
			}
		} else {
			gs.crab_anim_time = 0
		}
	}

	// 1. Latest WASD press sets queued direction.
	if !g.gs.is_rearranging_chunks {
		if      IsKeyDown(.W) || IsKeyDown(.UP) || IsGamepadButtonDown(0, .LEFT_FACE_UP) do gs.queued_direction = .Up
		else if IsKeyDown(.S) || IsKeyDown(.DOWN) || IsGamepadButtonDown(0, .LEFT_FACE_DOWN) do gs.queued_direction = .Down
		else if IsKeyDown(.A) || IsKeyDown(.LEFT) || IsGamepadButtonDown(0, .LEFT_FACE_LEFT) do gs.queued_direction = .Left
		else if IsKeyDown(.D) || IsKeyDown(.RIGHT) || IsGamepadButtonDown(0, .LEFT_FACE_RIGHT) do gs.queued_direction = .Right
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
	tilemap_pos_normalize_chunk(&gs.crab)

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

blinky_decision_order :: [4]Direction{ .Up, .Left, .Down, .Right }

// Exclude the reverse of current direction; pick neighbor whose tile minimizes
// squared distance to the target. If every forward option is blocked, reverse.
blinky_pick_direction :: proc(t: ^Tilemap, from: Tilemap_Pos, target: [2]int, current: Direction) -> Direction {
	reverse := opposite_direction(current)
	best := Direction.None
	best_dist := max(f32)

	for dir in blinky_decision_order {
		if dir == reverse do continue
		if !crab_can_step(t, from, dir) do continue

		step := direction_vector(dir)
		from_tile := tilemap_pos_absolute_tile(from)
		nx := from_tile.x + step.x
		ny := from_tile.y + step.y
		dx := f32(nx - target.x)
		dy := f32(ny - target.y)
		d  := dx*dx + dy*dy
		if d < best_dist {
			best_dist = d
			best = dir
		}
	}

	if best == .None && reverse != .None && crab_can_step(t, from, reverse) {
		best = reverse
	}
	return best
}

update_raccoon :: proc() {
	if !g.gs.raccoon_active do return
	if g.gs.game_over || g.gs.level_complete do return

	gs := &g.gs
	t  := &gs.level.tilemap

	defer tilemap_pos_normalize_chunk(&gs.raccoon)

	// Bootstrap: on first tick with no direction, pick one immediately.
	if gs.raccoon_direction == .None {
		target := tilemap_pos_absolute_tile(gs.crab)
		gs.raccoon_direction = blinky_pick_direction(t, gs.raccoon, target, .None)
		if gs.raccoon_direction == .None do return
	}

	dv := direction_vector(gs.raccoon_direction)
	dv_f := [2]f32{f32(dv.x), f32(dv.y)}
	pre_rel := gs.raccoon.rel_pos
	gs.raccoon.rel_pos += dv_f * gs.raccoon_move_speed * rl.GetFrameTime()

	crossed_cx := gs.raccoon.rel_pos.x
	crossed_cy := gs.raccoon.rel_pos.y
	crossed := false

	if dv.x != 0 {
		pre_u  := math.floor(pre_rel.x - 0.5)
		post_u := math.floor(gs.raccoon.rel_pos.x - 0.5)
		if pre_u != post_u {
			crossed = true
			u_cross := dv.x > 0 ? post_u : pre_u
			crossed_cx = u_cross + 0.5
		}
	}
	if dv.y != 0 {
		pre_u  := math.floor(pre_rel.y - 0.5)
		post_u := math.floor(gs.raccoon.rel_pos.y - 0.5)
		if pre_u != post_u {
			crossed = true
			u_cross := dv.y > 0 ? post_u : pre_u
			crossed_cy = u_cross + 0.5
		}
	}

	if !crossed do return

	// At the crossed tile center: snap, run Blinky AI, resume.
	saved_rel   := gs.raccoon.rel_pos
	saved_chunk := gs.raccoon.chunk
	gs.raccoon.rel_pos = {crossed_cx, crossed_cy}
	tilemap_pos_normalize_chunk(&gs.raccoon)

	target := tilemap_pos_absolute_tile(gs.crab)
	next_dir := blinky_pick_direction(t, gs.raccoon, target, gs.raccoon_direction)

	if next_dir == .None {
		// Completely boxed in (walls on all sides including behind). Stop here.
		gs.raccoon_direction = .None
		return
	}

	if next_dir == gs.raccoon_direction {
		// Straight through — preserve overshoot so movement stays smooth.
		gs.raccoon.rel_pos = saved_rel
		gs.raccoon.chunk   = saved_chunk
	} else {
		gs.raccoon_direction = next_dir
	}
}

update :: proc() {

	// NOTE(john): these are ints in here only because its easy to write in code
	// These are planned to be enum values once
	//... if we have an actual editor where we are placing these things

	tilemap := &g.gs.level.tilemap

	if rl.IsKeyPressed(.F3) do g.debug.show_overlay = !g.debug.show_overlay
	if rl.IsKeyPressed(.F4) do g.debug.paused = !g.debug.paused

	if rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}

	if rl.IsKeyPressed(.F10) do t_save_data()

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

		// Keep the active slot in sync while editing so swapping out doesn't lose work.
		// g.levels[g.gs.current_level_index] = g.gs.level

		for level_key, i in level_keys {
			if rl.IsKeyPressed(level_key) do swap_to_level(i)
		}
	}

	{ // cycle thru selected tile type
		tile_type_switch_key := rl.KeyboardKey.M
		if rl.IsKeyPressed(tile_type_switch_key) {
			g.editor_selected_tile_type = Tile_Type((int(g.editor_selected_tile_type)+1)%%len(Tile_Type))
		}
	}

	load_button := rl.KeyboardKey.F11
	if rl.IsKeyPressed(load_button) {
		t_load_data(context.temp_allocator)
	}

	if g.debug.paused do return

	if g.gs.game_over || g.gs.level_complete {
		a_pressed := rl.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) ||
		             rl.IsKeyPressed(.ENTER) ||
		             rl.IsKeyPressed(.SPACE)
		if a_pressed {
			next_i := g.gs.current_level_index
			if g.gs.level_complete {
				// Last-level completion loops back to level 0 for the "You Win" restart.
				next_i = g.gs.current_level_index == num_levels - 1 ? 0 : g.gs.current_level_index + 1
			}
			swap_to_level(next_i)
			g.gs.num_keys_crab_has = 0
			g.gs.elapsed_time      = 0
			g.gs.move_state        = .Idle
			g.gs.current_direction = .None
			g.gs.queued_direction  = .None
		}
	} else {
		g.gs.elapsed_time += rl.GetFrameTime()
	}

	{ // editor stuff
		mouse_screen := rl.GetMousePosition()
		mouse_world := rl.GetScreenToWorld2D(mouse_screen, game_camera())
		mouse_rel_tilemap := mouse_world - tilemap_world_origin(tilemap)
		tile_x := int(mouse_rel_tilemap.x) / tile_size
		tile_y := int(mouse_rel_tilemap.y) / tile_size

		place_crab_mod_key := rl.KeyboardKey.C
		if !rl.IsKeyDown(place_crab_mod_key) {
			if (rl.IsMouseButtonDown(.LEFT)) {
				tilemap_set_tile(tilemap, tile_x, tile_y, g.editor_selected_tile_type)
			} else if rl.IsMouseButtonDown(.RIGHT) {
				tilemap_set_tile(tilemap, tile_x, tile_y, .Trail)
			}
		} else {
			// NOTE(john) Only works when zoomed out
			if (rl.IsMouseButtonPressed(.LEFT)) {
				g.gs.crab = absolute_tile_to_tilemap_pos(tile_x, tile_y)
			}
		}

	}

	{
		enter_rearrange_mode_key := rl.KeyboardKey.Z
		enter_rearrange_mode_button := rl.GamepadButton.RIGHT_TRIGGER_1


		if IsKeyPressed(enter_rearrange_mode_key) || IsGamepadButtonPressed(0, enter_rearrange_mode_button) {
			g.gs.is_rearranging_chunks = true
			g.gs.zoom_timer = zoom_timer_duration_sec
			play_sound_by_name("zoom-out")
			rl.PauseMusicStream(g.drone_music)
			rl.ResumeMusicStream(g.dingdings_music)
		}

		if IsKeyReleased(enter_rearrange_mode_key) || IsGamepadButtonReleased(0, enter_rearrange_mode_button) {
			g.gs.is_rearranging_chunks = false
			g.gs.is_chunk_selection_active = false
			g.gs.zoom_timer = zoom_timer_duration_sec
			play_sound_by_name("zoom-in")
			rl.ResumeMusicStream(g.drone_music)
			rl.PauseMusicStream(g.dingdings_music)
		}


		crab_wpos : = tilemap_pos_to_world_pos(tilemap, g.gs.crab)


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

		if g.gs.swap_selection_change_timer > 0 {
			g.gs.swap_selection_change_timer -= rl.GetFrameTime()
			if g.gs.swap_selection_change_timer < 0 do g.gs.swap_selection_change_timer = 0
		}
	}

	if g.gs.is_rearranging_chunks {
		if IsKeyPressed(.UP) || IsGamepadButtonPressed(0, .LEFT_FACE_UP) {
			play_sound_by_name("ui-move-1")
			g.gs.hovered_chunk.y -= 1
		}
		if IsKeyPressed(.DOWN) || IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) {
			play_sound_by_name("ui-move-1")

			g.gs.hovered_chunk.y += 1
		}
		if IsKeyPressed(.LEFT) || IsGamepadButtonPressed(0, .LEFT_FACE_LEFT) {
			play_sound_by_name("ui-move-1")

			g.gs.hovered_chunk.x -= 1
		}
		if IsKeyPressed(.RIGHT) || IsGamepadButtonPressed(0, .LEFT_FACE_RIGHT) {
			play_sound_by_name("ui-move-1")

			g.gs.hovered_chunk.x += 1
		}

		if IsKeyPressed(.SPACE) || IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
			if g.gs.is_chunk_selection_active {
				g.gs.swap_selection_change_timer = zoom_timer_duration_sec
				
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
				g.gs.player_pos = tilemap_pos_to_world_pos(tilemap, g.gs.crab)

				g.gs.is_chunk_selection_active = false
			} else {
				play_sound_by_name("put-chunk")
				g.gs.swap_selection_change_timer = zoom_timer_duration_sec
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
	update_raccoon()

	if g.gs.move_state == .Moving && g.gs.prev_move_state != .Moving {
		rl.ResumeMusicStream(g.clickies_music)
	} else if g.gs.move_state != .Moving && g.gs.prev_move_state == .Moving {
		rl.PauseMusicStream(g.clickies_music)
	}
	g.gs.prev_move_state = g.gs.move_state

	if !g.gs.game_over && !g.gs.level_complete &&
	   g.gs.raccoon_active &&
	   tilemap_pos_absolute_tile(g.gs.crab) == tilemap_pos_absolute_tile(g.gs.raccoon) {
		play_sound_by_name("cluster")
		rl.PauseMusicStream(g.drone_music)
		g.gs.game_over  = true
		g.gs.move_state = .Idle
	}

	if !g.gs.game_over && !g.gs.level_complete { // crab reached the flag
		crab_tile := tilemap_pos_absolute_tile(g.gs.crab)
		if tilemap_get_tile_val(&g.gs.level.tilemap, crab_tile.x, crab_tile.y) == .Flag {
			play_sound_by_name("win")
			rl.PauseMusicStream(g.drone_music)
			g.gs.level_complete = true
			g.gs.move_state     = .Idle
		}
	}

	{ // crab get key
		crab_tile := tilemap_pos_absolute_tile(g.gs.crab)
		tile_type_that_crab_on := tilemap_get_tile_val(&g.gs.level.tilemap,
			crab_tile.x, crab_tile.y)
		crab_on_a_key := tile_type_that_crab_on == .Key
		if crab_on_a_key {
			tilemap_set_tile(&g.gs.level.tilemap, crab_tile.x, crab_tile.y, .Trail)
			g.gs.num_keys_crab_has+=1
			play_sound_by_name("chime")
		}
	}

	{ // crab make lock go away
		crab_next_tile := tilemap_pos_absolute_tile(g.gs.crab)
		switch g.gs.current_direction {
			case .Up: {
				crab_next_tile.y -= 1
			}
			case .Down: {
				crab_next_tile.y += 1
			}
			case .Left: {
				crab_next_tile.x -= 1
			}
			case .Right: {
				crab_next_tile.x += 1
			}
			case .None : {}
		}

		tile_type_that_next_tile_is := tilemap_get_tile_val(&g.gs.level.tilemap,
			crab_next_tile.x, crab_next_tile.y)

		can_crab_open_lock := tile_type_that_next_tile_is == .Lock &&
			g.gs.num_keys_crab_has > 0

		if can_crab_open_lock {
			tilemap_set_tile(&g.gs.level.tilemap, crab_next_tile.x, crab_next_tile.y, .Trail)
			g.gs.num_keys_crab_has-=1
			play_sound_by_name("unlock")
		}
	}


	rl.BeginTextureMode(g.render_texture)
	rl.ClearBackground(PALETTE_3)

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
					switch tile_type {
						case .Solid: {
							rect := rl.Rectangle {
								chunk_pos.x + (tile_size*f32(tile_x)),
								chunk_pos.y + (tile_size*f32(tile_y)),
								tile_size,
								tile_size,
							}
							rl.DrawRectangleRec(rect, PALETTE_4)
						}
						case .Trail: {
							rect := rl.Rectangle {
								chunk_pos.x + (tile_size*f32(tile_x)),
								chunk_pos.y + (tile_size*f32(tile_y)),
								tile_size,
								tile_size,
							}
							rl.DrawRectangleRec(rect, PALETTE_1)
						}
						case .Key:{
							rect := rl.Rectangle {
								chunk_pos.x + (tile_size*f32(tile_x)),
								chunk_pos.y + (tile_size*f32(tile_y)),
								tile_size,
								tile_size,
							}
							rl.DrawRectangleRec(rect, PALETTE_1)
							wpos := [2]f32 {
								chunk_pos.x + (tile_size*f32(tile_x)),
								chunk_pos.y + (tile_size*f32(tile_y)),
							}
							rl.DrawTextureV(g.key_texture, wpos, rl.WHITE)
						}
						case .Lock: {
							rect := rl.Rectangle {
								chunk_pos.x + (tile_size*f32(tile_x)),
								chunk_pos.y + (tile_size*f32(tile_y)),
								tile_size,
								tile_size,
							}
							rl.DrawRectangleRec(rect, PALETTE_1)
							wpos := [2]f32 {
								chunk_pos.x + (tile_size*f32(tile_x)),
								chunk_pos.y + (tile_size*f32(tile_y)),
							}
							rl.DrawTextureV(g.lock_texture, wpos, rl.WHITE)
						}
						case .Flag : {
							rect := rl.Rectangle {
								chunk_pos.x + (tile_size*f32(tile_x)),
								chunk_pos.y + (tile_size*f32(tile_y)),
								tile_size,
								tile_size,
							}
							rl.DrawRectangleRec(rect, PALETTE_1)
							wpos := [2]f32 {
								chunk_pos.x + (tile_size*f32(tile_x)),
								chunk_pos.y + (tile_size*f32(tile_y)),
							}
							rl.DrawTextureV(g.flag_texture, wpos, rl.WHITE)
						}
						case .Whatever: {
							rect := rl.Rectangle {
								chunk_pos.x + (tile_size*f32(tile_x)),
								chunk_pos.y + (tile_size*f32(tile_y)),
								tile_size,
								tile_size,
							}
							rl.DrawRectangleRec(rect, rl.WHITE)
						}
					}
				}
			}

			chunk_rect := rl.Rectangle {
				chunk_pos.x, chunk_pos.y, chunk_width_in_units, chunk_height_in_units
			}
			color := PALETTE_3
			color.a = 20
			rl.DrawRectangleLinesEx(chunk_rect, 4, color)
			// Note(john) using term chunk id to refer to the 2D index
			// which can really be thought of as an integer coordinate
			// system
			if g.gs.is_rearranging_chunks {
				chunk_id := [2]int{chunk_x, chunk_y}
					color := rl.BLACK

				if chunk_id == g.gs.hovered_chunk {
					color.a = 255
					rl.DrawRectangleLinesEx(chunk_rect, 20, color)
				} else if g.gs.is_chunk_selection_active {
					if chunk_id == g.gs.selected_chunk  {
						color = rl.GRAY
						rl.DrawRectangleLinesEx(chunk_rect, 20, color)
					}
				}
				is_selected := g.gs.is_chunk_selection_active && chunk_id == g.gs.selected_chunk
				is_hovered  := chunk_id == g.gs.hovered_chunk

				// Selected wins over hovered so the white border shows
				// immediately on the SPACE-press frame, before the player
				// moves the cursor off the selected chunk.
				if is_selected {
					color = rl.WHITE
					color.a = 255
				} else if is_hovered {
					color.a = 255
				}

			}
		}
	}

	chunk_pos := [2]f32 {0, 0}


	{ // DRAW CRAB
		tex := g.crabby_texture
		if g.gs.move_state == .Moving {
			frame := int(g.gs.crab_anim_time * crab_anim_fps) % crab_anim_frames
			tex = g.crab_walk_textures[frame]
		}
		// Sprite's default orientation faces Up, so rotate relative to that.
		rotation : f32 = 0
		switch g.gs.crab_facing {
		case .None, .Up: rotation = 0
		case .Right:     rotation = 90
		case .Down:      rotation = 180
		case .Left:      rotation = 270
		}
		src := rl.Rectangle{0, 0, f32(tex.width), f32(tex.height)}
		dst := rl.Rectangle{g.gs.player_pos.x, g.gs.player_pos.y, tile_size_f, tile_size_f}
		origin := [2]f32{tile_size_f * 0.5, tile_size_f * 0.5}
		rl.DrawTexturePro(tex, src, dst, origin, rotation, rl.WHITE)

		for key_index in 0..<g.gs.num_keys_crab_has {
			crab_wpos := tilemap_pos_to_world_pos(&g.gs.level.tilemap, g.gs.crab)
			space_from_crab := [2]f32{-16, -64}
			space_from_last_key := [2]f32{10,-10}
			key_wpos := crab_wpos + space_from_crab + (f32(key_index)*space_from_last_key)
			rl.DrawTextureV(g.key_texture, key_wpos, rl.WHITE)
		}

		crab_wpos := tilemap_pos_to_world_pos(&g.gs.level.tilemap, g.gs.crab)
		rl.DrawCircleV(crab_wpos, 4, rl.RED)
	}

	{ // instructions and ui guide stuff in camera
		if g.gs.current_level_index < 2 {
			rl.DrawTextureEx(g.dpad_crab_walk_texture, [2]f32{-310, -90}, {}, 0.6, rl.WHITE)

			// rl.DrawTextureV(g.move_crab_sticker_texture, [2]f32{-600, -100}, rl.WHITE)
		}
	}
	
	if g.gs.raccoon_active { // DRAW RACCOON
		// TODO: switch to animated frames when coon walk-cycle assets land.
		tex := g.coon_texture
		raccoon_wpos := tilemap_pos_to_world_pos(&g.gs.level.tilemap, g.gs.raccoon)
		src := rl.Rectangle{0, 0, f32(tex.width), f32(tex.height)}
		dst := rl.Rectangle{raccoon_wpos.x, raccoon_wpos.y, tile_size_f, tile_size_f}
		origin := [2]f32{tile_size_f * 0.5, tile_size_f * 0.5}
		rl.DrawTexturePro(tex, src, dst, origin, 0, rl.WHITE)
	}

	if g.debug.debug_draw {
		rl.DrawRectangleLinesEx({g.gs.player_pos.x - 8, g.gs.player_pos.y - 8, 16, 16}, 1, rl.MAGENTA)
		rl.DrawLineV({-5, 0}, {5, 0}, rl.YELLOW)
		rl.DrawLineV({0, -5}, {0, 5}, rl.YELLOW)
	}

	if g.gs.current_level_index == 0 {
		lc_text : cstring = "Lost crab"
    	lc_font_size : f32 = 64
    	lc_spacing   : f32 = 2
    	lc_size := rl.MeasureTextEx(g.lcd_font, lc_text, lc_font_size, lc_spacing)
    	lc_pos := [2]f32{
        	g.gs.camera_target.x - lc_size.x * 0.5,
            -350,
        }
		rl.DrawTextEx(g.lcd_font, lc_text, lc_pos, lc_font_size, lc_spacing, PALETTE_4)

		text : cstring = "in the"
    	font_size : f32 = 32
    	spacing   : f32 = 2
    	size := rl.MeasureTextEx(g.lcd_font, text, font_size, spacing)
    	pos := [2]f32{
        	g.gs.camera_target.x - size.x * 0.5,
            -280,
        }
		rl.DrawTextEx(g.lcd_font, text, pos, font_size, spacing, PALETTE_4)

		sub_text : cstring = "Great Sand Labyrnith"
    	sub_font_size : f32 = 56
    	sub_spacing   : f32 = 2
    	sub_size := rl.MeasureTextEx(g.lcd_font, sub_text, sub_font_size, sub_spacing)
    	sub_pos := [2]f32{
    	g.gs.camera_target.x - sub_size.x * 0.5,
            -242,
        }
		rl.DrawTextEx(g.lcd_font, sub_text, sub_pos, sub_font_size, sub_spacing, PALETTE_4)
	}

	rl.EndMode2D()

	{ // instructions and ui guide stuff outside of camera
		// if g.gs.current_level_index == 2 {
		// 	rl.DrawTextureV(g.a_button_panel_texture, [2]f32{10, 200}, rl.WHITE)
		// }

		if g.gs.current_level_index >= 2 {
			hidden_pos :=  [2]f32{
				f32(g.render_texture.texture.width) + 100, 10
			}
			visible_pos := [2]f32{
				f32(g.render_texture.texture.width) - 150, 10
			}

			dpad_hidden_pos := hidden_pos
			dpad_hidden_pos.y += 200
			dpad_visible_pos := visible_pos
			dpad_visible_pos.y += 200

			a_visible_pos := visible_pos
			a_hidden_pos := hidden_pos
			a_visible_pos.y += 430
			a_hidden_pos.y += 430


			hold_tex := g.right_bumper_hold_panel_texture
			release_tex := g.right_bumper_release_panel_texture
			dpad_tex := g.dpad_move_selection_texture
			dpad_crab_walk_tex := g.dpad_crab_walk_texture
			a_select_tex := g.a_button_select_texture
			a_swap_tex := g.a_button_swap_texture

			p := 1.0 - ((g.gs.zoom_timer / zoom_timer_duration_sec)*(g.gs.zoom_timer / zoom_timer_duration_sec))*(g.gs.zoom_timer / zoom_timer_duration_sec)
			p_inverse := ((g.gs.zoom_timer / zoom_timer_duration_sec)*(g.gs.zoom_timer / zoom_timer_duration_sec))*(g.gs.zoom_timer / zoom_timer_duration_sec)
			
			a_p := 1.0 - ((g.gs.swap_selection_change_timer / zoom_timer_duration_sec)*(g.gs.swap_selection_change_timer / zoom_timer_duration_sec))*(g.gs.swap_selection_change_timer / zoom_timer_duration_sec)

			hold_tex_pos := [2]f32{}
			release_tex_pos := [2]f32{}
			dpad_tex_pos := [2]f32 {}
			dpad_crab_walk_tex_pos := [2]f32{}
			a_select_tex_pos := [2]f32{}
			a_swap_tex_pos := [2]f32{}

			if g.gs.is_rearranging_chunks {
				hold_tex_p := p
				release_tex_p := p_inverse

				hold_tex_pos = linalg.lerp(visible_pos, hidden_pos, p)
				dpad_tex_pos = linalg.lerp(dpad_hidden_pos, dpad_visible_pos, p)
				dpad_crab_walk_tex_pos = linalg.lerp(dpad_visible_pos, dpad_hidden_pos, p)

				release_tex_pos = linalg.lerp(hidden_pos, visible_pos, p)

				a_select_tex_pos = linalg.lerp(a_hidden_pos, a_visible_pos, p)

				if g.gs.is_chunk_selection_active {
					a_select_tex_pos = linalg.lerp(a_visible_pos, a_hidden_pos, a_p)
					a_swap_tex_pos = linalg.lerp(a_hidden_pos, a_visible_pos, a_p)
				} else {
					if g.gs.swap_selection_change_timer > 0 {
						a_select_tex_pos = linalg.lerp(a_hidden_pos, a_visible_pos, a_p)
					}
					a_swap_tex_pos = linalg.lerp(a_visible_pos, a_hidden_pos, a_p)
				}
			} else {
				hold_tex_p := p_inverse
				release_tex_p := p

				release_tex_pos = linalg.lerp(visible_pos, hidden_pos, p)
				hold_tex_pos = linalg.lerp(hidden_pos, visible_pos, p)

				dpad_tex_pos = linalg.lerp(dpad_visible_pos, dpad_hidden_pos,  p)

				dpad_crab_walk_tex_pos = linalg.lerp(dpad_hidden_pos, dpad_visible_pos, p)

				a_select_tex_pos = linalg.lerp(a_visible_pos, a_hidden_pos, p)

				if g.gs.is_chunk_selection_active {
					a_swap_tex_pos = linalg.lerp(a_visible_pos, a_hidden_pos, p)
				} else {
					a_swap_tex_pos = a_hidden_pos
				}
			}

			rl.DrawTextureEx(hold_tex, hold_tex_pos, {}, 0.5, rl.WHITE)
			rl.DrawTextureEx(release_tex, release_tex_pos,  {}, 0.5, rl.WHITE)
			rl.DrawTextureEx(dpad_tex, dpad_tex_pos, {}, 0.6, rl.WHITE)
			rl.DrawTextureEx(a_select_tex, a_select_tex_pos, {}, 0.6, rl.WHITE)
			rl.DrawTextureEx(a_swap_tex, a_swap_tex_pos, {}, 0.6, rl.WHITE)
			rl.DrawTextureEx(dpad_crab_walk_tex, dpad_crab_walk_tex_pos, {}, 0.6, rl.WHITE)
		} else {
			// dpad_crab_walk_tex := g.dpad_crab_walk_texture


			// visible_pos := [2]f32{
			// 	f32(g.render_texture.texture.width) - 150, 10
			// }
			// rl.DrawTextureEx(dpad_crab_walk_tex, visible_pos, {}, 0.6, rl.WHITE)

		}
	}

	// Debug overlay is drawn in screen space (no camera) so its controls sit
	// on top of everything. `fmt.ctprintf` uses the temp allocator, which is
	// freed at end-of-frame by the host in main_hot_reload.odin /
	// main_release.odin / main_web_entry.odin.

	hud_rect := rl.Rectangle{ 8, 8, f32(g.render_texture.texture.width) / 6, 120 }
	rl.DrawRectangleRounded       (hud_rect, 0.15, 8,    PALETTE_1)
	rl.DrawRectangleRoundedLinesEx(hud_rect, 0.15, 8, 3, PALETTE_4)

	minutes := int(g.gs.elapsed_time) / 60
	seconds := int(g.gs.elapsed_time) % 60

	rl.DrawTextEx(g.lcd_font, "TIME", {20, 12}, 40, 2, PALETTE_4)
	rl.DrawTextEx(
		g.lcd_font,
		fmt.ctprintf("%02d:%02d", minutes, seconds),
		{20, 52},
		72,
		2,
		PALETTE_4,
	)

	if g.gs.game_over {
		draw_popup("Coon got ya", "", "Hit A to play again")
	} else if g.gs.level_complete {
		time_str := fmt.ctprintf("%02d:%02d", minutes, seconds)
		if g.gs.current_level_index == num_levels - 1 {
			draw_popup("You Win", time_str, "Hit A to play again")
		} else {
			draw_popup("Level Complete", time_str, "Hit A to continue")
		}
	}

	rl.EndTextureMode()


	{ // DRAW TO WINDOW
		rl.BeginDrawing()
		defer rl.EndDrawing()

		rl.ClearBackground(rl.BLACK)

		screen_width := f32(rl.GetScreenWidth())
		screen_height := f32(rl.GetScreenHeight())

		scale := min(
			screen_width  / f32(g.render_texture.texture.width),
			screen_height / f32(g.render_texture.texture.height),
		)
		window_scaled_width  := f32(g.render_texture.texture.width)  * scale
		window_scaled_height := f32(g.render_texture.texture.height) * scale

		src := rl.Rectangle{ 0, 0, f32(g.render_texture.texture.width), f32(-g.render_texture.texture.height) }
		dst := rl.Rectangle{
			(screen_width  - window_scaled_width)  / 2,
			(screen_height - window_scaled_height) / 2,
			window_scaled_width,
			window_scaled_height,
		}
		rl.DrawTexturePro(g.render_texture.texture, src, dst, [2]f32{0,0}, 0, rl.WHITE)



		draw_debug_overlay()

	}
}