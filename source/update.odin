package game

// NOTE(johnb) only reason putting in here is i found i often
// want to just see update stuff in one pane,
// and anything else in the other pane at the same time

import rl "vendor:raylib"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"

blinky_pick_direction2 :: proc(tm : ^Tilemap, entity_tmpos : Tilemap_Pos,
	curr_dir : Direction, target_tile : [2]int) -> Direction {
	
	next_dir := curr_dir
	
	current_entity_tile := tilemap_pos_absolute_tile(entity_tmpos)

	adjacent_tiles : [Direction][2]int
	adjacent_tiles[.None] = current_entity_tile

	adjacent_tiles[.Left] = current_entity_tile
	adjacent_tiles[.Left].x -= 1

	adjacent_tiles[.Right] = current_entity_tile
	adjacent_tiles[.Right].x += 1

	adjacent_tiles[.Up] = current_entity_tile
	adjacent_tiles[.Up].y -= 1

	adjacent_tiles[.Down] = current_entity_tile
	adjacent_tiles[.Down].y += 1

	target_wcenter := tile_center_world(tm, target_tile.x, target_tile.y)

	adjacent_tile_world_centers : [Direction][2]f32

	for adjacent_tile, dir in adjacent_tiles {
		wcenter := tile_center_world(tm, adjacent_tile.x, adjacent_tile.y)
		adjacent_tile_world_centers[dir] = wcenter			
	}

	adjacent_tile_distances_from_target_tile := [Direction]f32{}

	for wcenter, dir in adjacent_tile_world_centers {
		distance_from_target := linalg.distance(wcenter, target_wcenter)
		adjacent_tile_distances_from_target_tile[dir] = distance_from_target
	}

	closest_tile_direction_to_target := Direction.None
	closest_distance : f32 = 99999

	// avoids checking opposite direction and .none
	for distance, dir in adjacent_tile_distances_from_target_tile {
		tile := adjacent_tiles[dir]
		
		in_bounds := tilemap_is_coord_in_bounds(tm, tile.x, tile.y)
		is_opposite_dir := dir == opposite_direction(curr_dir)
		is_none := dir == .None
		is_walkable := tilemap_is_walkable(tm, tile.x, tile.y)

		is_valid_dir := in_bounds && 
			 !is_opposite_dir &&
			 !is_none &&
			 is_walkable

		if is_valid_dir {
			is_closer := distance < closest_distance
			if is_closer {
				closest_distance = distance
				closest_tile_direction_to_target = dir
			}
		}
	}

	next_tile := current_entity_tile

	found_valid_closest_adjacent_tile := closest_tile_direction_to_target != .None
	if found_valid_closest_adjacent_tile {
		next_tile = adjacent_tiles[closest_tile_direction_to_target]
		next_dir = closest_tile_direction_to_target
	} else {
		raccoon_opposite_direction := opposite_direction(curr_dir)
		opposite_direction_tile := adjacent_tiles[raccoon_opposite_direction]
		can_turn_around := tilemap_is_walkable(tm, opposite_direction_tile.x, opposite_direction_tile.y)
		if can_turn_around {
			next_tile = adjacent_tiles[raccoon_opposite_direction]
			next_dir = raccoon_opposite_direction
		} else {
			next_dir = .None
		}
	}
	
	return next_dir
}


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

	rl.SetMusicVolume(g.drone_music, 0.15)
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


// Web-only startup screen. Shown until the user clicks/presses a button, which
// (a) dismisses the popup and (b) satisfies the browser's user-gesture
// requirement so the suspended AudioContext can resume. Self-contained render
// pipeline so update() can return early without touching gameplay state.
draw_web_audio_unlock_screen :: proc() {
	unlock := rl.IsMouseButtonPressed(.LEFT) ||
	          IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) ||
	          rl.IsKeyPressed(.ENTER) ||
	          rl.IsKeyPressed(.SPACE)
	if unlock {
		g.gs.awaiting_audio_unlock = false
	}

	rl.BeginTextureMode(g.render_texture)
	rl.ClearBackground(PALETTE_3)
	draw_popup("Click me", "or", "Press A button")
	rl.EndTextureMode()

	rl.BeginDrawing()
	defer rl.EndDrawing()
	rl.ClearBackground(rl.BLACK)

	screen_width  := f32(rl.GetScreenWidth())
	screen_height := f32(rl.GetScreenHeight())
	scale := min(
		screen_width  / f32(g.render_texture.texture.width),
		screen_height / f32(g.render_texture.texture.height),
	)
	ws := f32(g.render_texture.texture.width)  * scale
	hs := f32(g.render_texture.texture.height) * scale

	src := rl.Rectangle{0, 0, f32(g.render_texture.texture.width), f32(-g.render_texture.texture.height)}
	dst := rl.Rectangle{(screen_width - ws) / 2, (screen_height - hs) / 2, ws, hs}
	rl.DrawTexturePro(g.render_texture.texture, src, dst, [2]f32{0,0}, 0, rl.WHITE)
}

data_file_filename :: "data"

// t_save_data :: proc() {

// 	g.gs.level.crab_start_pos = g.gs.crab
// 	g.gs.level.raccoon_start_pool = g.gs.raccoon_pool

// 	g.levels[g.gs.current_level_index] = g.gs.level
// 	g.initial_current_level = g.gs.level

// 	s : Serializer
// 	serializer_init_writer(&s, allocator = context.temp_allocator)
// 	serialize(&s, &g.levels)
// 	werr := os.write_entire_file(data_file_filename, s.data[:])
// 	if werr != nil {
// 		fmt.printfln("error writing file to data file")
// 	}
// }

t_load_data :: proc(allocator : runtime.Allocator = context.allocator) -> bool {

	s : Serializer
	data, success := read_entire_file_from_path(data_file_filename, allocator)
	if success {
		serializer_init_reader(&s, data[:])
		ok := serialize(&s, &g.levels)
		if !ok  {
			fmt.printfln("error serializing reader")
			return false
		}

	} else {
		fmt.printfln("error reading from data file")
		return false
	}



	return true
}

// Centered modal popup using the HUD's rounded-rect style.
// Caller passes screen-center-aligned text lines; pass "" for any middle line to collapse it out.
draw_popup :: proc(heading, middle, footer: cstring, middle2: cstring = "") {
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
	middle_size  : f32 = 36
	middle2_size : f32 = 56
	footer_size  : f32 = 32
	spacing      : f32 = 2
	gap          : f32 = 20

	has_middle  := len(string(middle))  > 0
	has_middle2 := len(string(middle2)) > 0

	h_dim  := rl.MeasureTextEx(g.lcd_font, heading, heading_size, spacing)
	m_dim  : [2]f32
	m2_dim : [2]f32
	if has_middle  do m_dim  = rl.MeasureTextEx(g.lcd_font, middle,  middle_size,  spacing)
	if has_middle2 do m2_dim = rl.MeasureTextEx(g.lcd_font, middle2, middle2_size, spacing)
	f_dim := rl.MeasureTextEx(g.lcd_font, footer, footer_size, spacing)

	total_h := h_dim.y + gap + f_dim.y
	if has_middle  do total_h += m_dim.y  + gap
	if has_middle2 do total_h += m2_dim.y + gap

	center_x := popup_x + popup_w * 0.5
	y := popup_y + (popup_h - total_h) * 0.5

	rl.DrawTextEx(g.lcd_font, heading, {center_x - h_dim.x * 0.5, y}, heading_size, spacing, PALETTE_4)
	y += h_dim.y + gap

	if has_middle {
		rl.DrawTextEx(g.lcd_font, middle, {center_x - m_dim.x * 0.5, y}, middle_size, spacing, PALETTE_4)
		y += m_dim.y + gap
	}

	if has_middle2 {
		rl.DrawTextEx(g.lcd_font, middle2, {center_x - m2_dim.x * 0.5, y}, middle2_size, spacing, PALETTE_4)
		y += m2_dim.y + gap
	}

	rl.DrawTextEx(g.lcd_font, footer, {center_x - f_dim.x * 0.5, y}, footer_size, spacing, PALETTE_4)
}

swap_to_level :: proc(i: int) {
	g.gs.current_level_index = i
	g.initial_current_level = g.levels[i]
	g.gs.level = g.initial_current_level
	g.gs.crab = g.initial_current_level.crab_start_pos
	g.gs.raccoon_pool = g.initial_current_level.raccoon_start_pool


	g.gs.game_over      = false
	g.gs.level_complete = false
	g.gs.raccoon_spawn_delay = raccoon_spawn_delay_duration

	rl.ResumeMusicStream(g.drone_music)
	rl.PauseMusicStream(g.dingdings_music)

	// g.initial_current_level
	// g.levels[g.gs.current_level_index] = g.initial_current_level
	// g.gs.level = g.levels[i]
	// g.gs.crab = g.gs.level.crab_start_pos

	g.gs.num_keys_crab_has = 0
}

// spawn_raccoon_opposite_crab :: proc() {
// 	t := &g.gs.level.tilemap
// 	crab_tile := tilemap_pos_absolute_tile(g.gs.crab)
// 	target_x := t.width  - 1 - crab_tile.x
// 	target_y := t.height - 1 - crab_tile.y

// 	// Spiral outward from the opposite corner until we land on a walkable tile.
// 	// Guaranteed to terminate because the crab's own tile is walkable.
// 	max_radius := t.width + t.height
// 	found_x, found_y := target_x, target_y
// 	search: for radius in 0..=max_radius {
// 		for dy in -radius..=radius {
// 			for dx in -radius..=radius {
// 				if abs(dx) != radius && abs(dy) != radius do continue
// 				tx := target_x + dx
// 				ty := target_y + dy
// 				if tx < 0 || tx >= t.width || ty < 0 || ty >= t.height do continue
// 				if tx == crab_tile.x && ty == crab_tile.y do continue
// 				if tilemap_is_walkable(t, tx, ty) {
// 					found_x = tx
// 					found_y = ty
// 					break search
// 				}
// 			}
// 		}
// 	}

// 	g.gs.raccoon = absolute_tile_to_tilemap_pos(found_x, found_y)
// 	g.gs.raccoon_direction = .None
// 	raccoon_move_speed = 3.0
// }

raccoon_move_speed : f32 = 3.0


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

try_open_adjacent_lock :: proc(t: ^Tilemap, cp: Tilemap_Pos, dir: Direction) -> bool {
	if dir == .None do return false
	if g.gs.num_keys_crab_has <= 0 do return false
	step := direction_vector(dir)
	tile := tilemap_pos_absolute_tile(cp)
	tx := tile.x + step.x
	ty := tile.y + step.y
	if tilemap_get_tile_val(t, tx, ty) != .Lock do return false
	tilemap_set_tile(t, tx, ty, .Trail)
	g.gs.num_keys_crab_has -= 1
	play_sound_by_name("unlock")
	return true
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
		try_open_adjacent_lock(t, gs.crab, gs.queued_direction)
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
		try_open_adjacent_lock(t, gs.crab, gs.queued_direction)
		if crab_can_step(t, gs.crab, gs.queued_direction) {
			gs.current_direction = gs.queued_direction
			turned = true
		}
	}
	gs.queued_direction = .None

	if !turned {
		try_open_adjacent_lock(t, gs.crab, gs.current_direction)
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

// BFS walking distance from (sx, sy) over raccoon-traversable tiles into out
// (size t.width*t.height). Mirrors tilemap_is_walkable: Solid and Lock are walls.
tilemap_bfs_distances :: proc(t: ^Tilemap, sx, sy: int, out: []int) {
	for i in 0..<len(out) do out[i] = max(int)
	if !tilemap_is_coord_in_bounds(t, sx, sy) do return
	queue : [max_tiles][2]int
	head, tail : int
	queue[tail] = {sx, sy}; tail += 1
	out[sy*t.width + sx] = 0
	steps := [4][2]int{{0,-1}, {0,1}, {-1,0}, {1,0}}
	for head < tail {
		p := queue[head]; head += 1
		d := out[p.y*t.width + p.x]
		for s in steps {
			nx := p.x + s.x
			ny := p.y + s.y
			if !tilemap_is_coord_in_bounds(t, nx, ny) do continue
			tt := t.tiles[ny*t.width + nx]
			if tt == .Solid || tt == .Lock do continue
			if out[ny*t.width + nx] != max(int) do continue
			out[ny*t.width + nx] = d + 1
			queue[tail] = {nx, ny}; tail += 1
		}
	}
}

// Exclude the reverse of current direction; pick neighbor that minimizes BFS
// walking distance to the target. If every forward option is blocked, reverse.
blinky_pick_direction :: proc(t: ^Tilemap, from: Tilemap_Pos, target: [2]int, current: Direction) -> Direction {
	dists : [max_tiles]int
	tilemap_bfs_distances(t, target.x, target.y, dists[:])

	reverse := opposite_direction(current)
	best := Direction.None
	best_d := max(int)
	from_tile := tilemap_pos_absolute_tile(from)

	for dir in blinky_decision_order {
		if dir == reverse do continue
		if !crab_can_step(t, from, dir) do continue

		step := direction_vector(dir)
		nx := from_tile.x + step.x
		ny := from_tile.y + step.y
		if !tilemap_is_coord_in_bounds(t, nx, ny) do continue
		d := dists[ny*t.width + nx]
		// First walkable forward seeds best so an unreachable target (all max(int))
		// still picks SOMETHING; subsequent dirs only win on strictly closer.
		if best == .None || d < best_d {
			best_d = d
			best = dir
		}
	}

	if best == .None && reverse != .None && crab_can_step(t, from, reverse) {
		best = reverse
	}
	return best
}

is_between :: proc(val, bound_a, bound_b : f32) -> bool {
	lo := min(bound_a, bound_b)
	hi := max(bound_a, bound_b)
	ret := false
	if lo < val && val <= hi {
		ret = true
	}
	return ret
}

update_raccoon :: proc(dt, speed_mod : f32) {
	if g.gs.game_over || g.gs.level_complete do return

	if g.gs.raccoon_spawn_delay > 0 {
		g.gs.raccoon_spawn_delay -= rl.GetFrameTime()
		return
	}

	for &raccoon in g.gs.raccoon_pool {
		if !raccoon.active do continue

		gs := &g.gs
		t  := &gs.level.tilemap

		defer tilemap_pos_normalize_chunk(&raccoon.pos)

		// Bootstrap: on first tick with no direction, pick one immediately.
		if raccoon.direction == .None {
			target := tilemap_pos_absolute_tile(gs.crab)
			raccoon.direction = blinky_pick_direction(t, raccoon.pos, target, .None)
			if raccoon.direction == .None do continue
		}

		dv := direction_vector(raccoon.direction)
		dv_f := [2]f32{f32(dv.x), f32(dv.y)}
		move_speed := raccoon_move_speed
		if g.gs.is_rearranging_chunks {
			move_speed *= 0.1
		}
		
		capped_frame_time := min(rl.GetFrameTime(), 0.016)
		
		old_rel_pos := raccoon.pos.rel_pos		
		test_new_rel_pos := raccoon.pos.rel_pos + 
			(dv_f * move_speed * capped_frame_time)
		new_rel_pos := test_new_rel_pos

		curr_chunk_tile := rel_pos_to_chunk_absolute_tile(old_rel_pos)
		curr_chunk_tile_center_pos := chunk_tile_to_center_pos(curr_chunk_tile)

		did_cross_x := is_between(curr_chunk_tile_center_pos.x, old_rel_pos.x, test_new_rel_pos.x)
		did_cross_y := is_between(curr_chunk_tile_center_pos.y, old_rel_pos.y, test_new_rel_pos.y)

		should_snap_on_curr_tile_center_x := did_cross_x 
		should_snap_on_curr_tile_center_y := did_cross_y
		
		if should_snap_on_curr_tile_center_x {
			new_rel_pos.x = curr_chunk_tile_center_pos.x
		} 
		else if should_snap_on_curr_tile_center_y {
			new_rel_pos.y = curr_chunk_tile_center_pos.y
		}

		// COMMIT TO NEW POSITION
		raccoon.pos.rel_pos = new_rel_pos
		tilemap_pos_normalize_chunk(&raccoon.pos)

		should_pick_new_direction := did_cross_x || did_cross_y
		if should_pick_new_direction {

			target := tilemap_pos_absolute_tile(gs.crab)
			next_dir := blinky_pick_direction2(t, raccoon.pos, raccoon.direction, target)

			overshoot : f32 = 0
			if did_cross_x {
				overshoot = abs(test_new_rel_pos.x - curr_chunk_tile_center_pos.x)
			} else if did_cross_y {
				overshoot = abs(test_new_rel_pos.y - curr_chunk_tile_center_pos.y)
			}

			if next_dir == .Left {
				raccoon.pos.rel_pos.x -= overshoot
			} else if next_dir == .Right {
				raccoon.pos.rel_pos.x += overshoot
			} else if next_dir == .Up {
				raccoon.pos.rel_pos.y -= overshoot
			} else if next_dir == .Down {
				raccoon.pos.rel_pos.y += overshoot
			}

			raccoon.direction = next_dir
		}
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

	when ODIN_OS == .JS {
		if g.gs.awaiting_audio_unlock {
			draw_web_audio_unlock_screen()
			return
		}
	}

	// if rl.IsKeyPressed(.F10) do t_save_data()

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

	when ODIN_OS != .JS {
		if rl.IsKeyPressed(.F11) {
			toggle_fullscreen()
		}
	}

	// load_button := rl.KeyboardKey.F11
	// if rl.IsKeyPressed(load_button) {
	// 	t_load_data(context.temp_allocator)
	// }

	if g.debug.paused do return

	is_in_transition_popup := g.gs.game_over || g.gs.level_complete

	if !is_in_transition_popup{
		enter_rearrange_keys := [?]rl.KeyboardKey{.Z, .LEFT_SHIFT, .RIGHT_SHIFT}
		enter_rearrange_mode_button := rl.GamepadButton.RIGHT_TRIGGER_1

		enter_rearrange_mode := IsAnyKeysPressed(..enter_rearrange_keys[:]) ||
			IsGamepadButtonPressed(0, enter_rearrange_mode_button)

		if enter_rearrange_mode {
			g.gs.is_rearranging_chunks = true
			g.gs.zoom_timer = zoom_timer_duration_sec
			play_sound_by_name("zoom-out")
			rl.PauseMusicStream(g.drone_music)
			rl.ResumeMusicStream(g.dingdings_music)
		}

		if g.gs.is_rearranging_chunks {
			exit_rearrange_mode := IsAnyKeysReleased(..enter_rearrange_keys[:]) ||
				IsGamepadButtonReleased(0, enter_rearrange_mode_button)

			if exit_rearrange_mode {
				g.gs.is_rearranging_chunks = false
				g.gs.is_chunk_selection_active = false
				g.gs.zoom_timer = zoom_timer_duration_sec
				play_sound_by_name("zoom-in")
				rl.ResumeMusicStream(g.drone_music)
				rl.PauseMusicStream(g.dingdings_music)
			}

		}

		toggle_rearrange := IsGamepadButtonPressed(0, .LEFT_TRIGGER_1) ||
			IsKeyPressed(.C)
		if toggle_rearrange {
			if g.gs.is_rearranging_chunks {
				g.gs.is_chunk_selection_active = false
				rl.ResumeMusicStream(g.drone_music)
				rl.PauseMusicStream(g.dingdings_music)
			} else {
				rl.PauseMusicStream(g.drone_music)
				rl.ResumeMusicStream(g.dingdings_music)
			}
			g.gs.is_rearranging_chunks = !g.gs.is_rearranging_chunks
			g.gs.zoom_timer = zoom_timer_duration_sec
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



	when ODIN_OS != .JS { // editor stuff — native-only dev tooling
		mouse_screen := rl.GetMousePosition()
		mouse_world := rl.GetScreenToWorld2D(mouse_screen, game_camera())
		mouse_rel_tilemap := mouse_world - tilemap_world_origin(tilemap)
		tile_x := int(mouse_rel_tilemap.x) / tile_size
		tile_y := int(mouse_rel_tilemap.y) / tile_size

		place_crab_mod_key := rl.KeyboardKey.C
		place_coon_mod_key := rl.KeyboardKey.V

		if !rl.IsKeyDown(place_crab_mod_key) && !rl.IsKeyDown(place_coon_mod_key) {
			if (rl.IsMouseButtonDown(.LEFT)) {
				tilemap_set_tile(tilemap, tile_x, tile_y, g.editor_selected_tile_type)
			} else if rl.IsMouseButtonDown(.RIGHT) {
				tilemap_set_tile(tilemap, tile_x, tile_y, .Trail)
			}
		} else if rl.IsKeyDown(place_crab_mod_key) {
			// NOTE(john) Only works when zoomed out
			if (rl.IsMouseButtonPressed(.LEFT)) {
				g.gs.crab = absolute_tile_to_tilemap_pos(tile_x, tile_y)
			}
		} else if rl.IsKeyDown(place_coon_mod_key) {
			if (rl.IsMouseButtonPressed(.LEFT)) {
				// set first active raccoon
				for &raccoon in g.gs.raccoon_pool {
					if !raccoon.active {
						tilemap_pos_clicked := absolute_tile_to_tilemap_pos(tile_x, tile_y)
						raccoon.pos = tilemap_pos_clicked
						raccoon.direction = .None
						raccoon.active = true
						break
					}
				}
			} else if (rl.IsMouseButtonPressed(.RIGHT)) {
				// rid any raccoons in tile
				for &raccoon in g.gs.raccoon_pool {
					if raccoon.active {
						tilemap_pos_clicked := absolute_tile_to_tilemap_pos(tile_x, tile_y)
						tile_clicked := tilemap_pos_absolute_tile(tilemap_pos_clicked)
						raccoon_tile := tilemap_pos_absolute_tile(raccoon.pos )
						if tile_clicked == raccoon_tile {
							raccoon.active = false
						}
					}
				}
			}
		}

		if !rl.IsKeyDown(place_coon_mod_key) {
			if (rl.IsMouseButtonDown(.LEFT)) {
				tilemap_set_tile(tilemap, tile_x, tile_y, g.editor_selected_tile_type)
			} else if rl.IsMouseButtonDown(.RIGHT) {
				tilemap_set_tile(tilemap, tile_x, tile_y, .Trail)
			}
		} else {
			// NOTE(john) Only works when zoomed out

		}


	}



	if g.gs.is_rearranging_chunks {
		if IsAnyKeysPressed(.UP, .W) || IsGamepadButtonPressed(0, .LEFT_FACE_UP) {
			play_sound_by_name("ui-move-1")
			g.gs.hovered_chunk.y -= 1
		}
		if IsAnyKeysPressed(.DOWN, .S) || IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) {
			play_sound_by_name("ui-move-1")

			g.gs.hovered_chunk.y += 1
		}
		if IsAnyKeysPressed(.LEFT, .A) || IsGamepadButtonPressed(0, .LEFT_FACE_LEFT) {
			play_sound_by_name("ui-move-1")

			g.gs.hovered_chunk.x -= 1
		}
		if IsAnyKeysPressed(.RIGHT, .D) || IsGamepadButtonPressed(0, .LEFT_FACE_RIGHT) {
			play_sound_by_name("ui-move-1")

			g.gs.hovered_chunk.x += 1
		}

		swap_chunk := IsAnyKeysPressed(.SPACE, .X) || IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN)

		if swap_chunk {
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
				// so do raccoons
				for &raccoon in g.gs.raccoon_pool {
					if raccoon.pos.chunk == g.gs.hovered_chunk {
						raccoon.pos.chunk = g.gs.selected_chunk
					} else if raccoon.pos.chunk == g.gs.selected_chunk {
						raccoon.pos.chunk = g.gs.hovered_chunk
					}
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

	if rl.IsKeyPressed(.ENTER) {
		g.dev_paused = !g.dev_paused
	}

	dt := min(rl.GetFrameTime(), 0.1666666)
	speed_mod : f32 = g.gs.is_rearranging_chunks ? 0.1 : 1.0
	
	if !g.dev_paused {
		update_crab()
		update_raccoon(dt, speed_mod)
	}

	did_any_raccoons_get_crab := false
	for raccoon in g.gs.raccoon_pool {
		if raccoon.active {
			did_any_raccoons_get_crab |=  tilemap_pos_absolute_tile(g.gs.crab) == tilemap_pos_absolute_tile(raccoon.pos)
		}
	}

	if !g.gs.game_over && !g.gs.level_complete && did_any_raccoons_get_crab {
		// TODO: swap to a dedicated raccoon-hit sfx once the asset lands.
		play_sound_by_name("smack")
		play_sound_by_name("cluster")
		rl.PauseMusicStream(g.drone_music)
		g.gs.game_over  = true
		g.gs.move_state = .Idle
	}

	walking_gameplay := g.gs.move_state == .Moving && !g.gs.is_rearranging_chunks
	if walking_gameplay && !g.gs.prev_walking_gameplay {
		rl.ResumeMusicStream(g.clickies_music)
	} else if !walking_gameplay && g.gs.prev_walking_gameplay {
		rl.PauseMusicStream(g.clickies_music)
	}
	g.gs.prev_walking_gameplay = walking_gameplay

	// if !g.gs.game_over && !g.gs.level_complete &&
	//    g.gs.raccoon_active &&
	//    tilemap_pos_absolute_tile(g.gs.crab) == tilemap_pos_absolute_tile(g.gs.raccoon) {

	// }

	if !g.gs.game_over && !g.gs.level_complete { // crab reached the flag
		crab_tile := tilemap_pos_absolute_tile(g.gs.crab)
		if tilemap_get_tile_val(&g.gs.level.tilemap, crab_tile.x, crab_tile.y) == .Flag {
			rl.PauseMusicStream(g.drone_music)
			if g.gs.current_level_index == num_levels - 1 {
				// Final level — credits popup runs dingdings instead of the win sting.
				rl.ResumeMusicStream(g.dingdings_music)
			} else {
				play_sound_by_name("win")
			}
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
				chunk_pos.x, chunk_pos.y, chunk_width_in_units, chunk_height_in_units,
			}
			chunk_color := PALETTE_3
			chunk_color.a = 20
			if g.gs.is_rearranging_chunks {
				chunk_color.a = 200
			}
			rl.DrawRectangleLinesEx(chunk_rect, 4, chunk_color)
			// Note(john) using term chunk id to refer to the 2D index
			// which can really be thought of as an integer coordinate
			// system
			if g.gs.is_rearranging_chunks {
				chunk_id := [2]int{chunk_x, chunk_y}
				color := rl.BLACK

				if g.gs.is_chunk_selection_active {
					if chunk_id == g.gs.selected_chunk  {
						color = rl.WHITE
						color.a = 200
						rl.DrawRectangleLinesEx(chunk_rect, 30, color)
					}
				}

				if chunk_id == g.gs.hovered_chunk {
					color.a = 255
					black := rl.BLACK
					black.a = 150
					rl.DrawRectangleLinesEx(chunk_rect, 20, black)
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

		// crab_wpos := tilemap_pos_to_world_pos(&g.gs.level.tilemap, g.gs.crab)
		// rl.DrawCircleV(crab_wpos, 4, rl.RED)
	}

	{ // instructions and ui guide stuff in camera
		if g.gs.current_level_index < 2 {
			rl.DrawTextureEx(g.dpad_crab_walk_texture, [2]f32{-310, -90}, {}, 0.6, rl.WHITE)

			// rl.DrawTextureV(g.move_crab_sticker_texture, [2]f32{-600, -100}, rl.WHITE)
		}
	}

	raccoon_frame := 0
	if g.gs.raccoon_spawn_delay <= 0 {
		raccoon_frame = int(g.gs.elapsed_time * raccoon_anim_fps) %% raccoon_anim_frames
	}
	raccoon_tex := g.raccoon_walk_textures[raccoon_frame]
	for raccoon in g.gs.raccoon_pool {
		if raccoon.active { // DRAW RACCOON
			raccoon_wpos := tilemap_pos_to_world_pos(&g.gs.level.tilemap, raccoon.pos)
			src := rl.Rectangle{0, 0, f32(raccoon_tex.width), f32(raccoon_tex.height)}
			dst := rl.Rectangle{raccoon_wpos.x, raccoon_wpos.y, tile_size_f, tile_size_f}
			origin := [2]f32{tile_size_f * 0.5, tile_size_f * 0.5}
			rl.DrawTexturePro(raccoon_tex, src, dst, origin, 0, rl.WHITE)
		}
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

		sub_text : cstring = "Great Sand Labyrinth"
    	sub_font_size : f32 = 56
    	sub_spacing   : f32 = 2
    	sub_size := rl.MeasureTextEx(g.lcd_font, sub_text, sub_font_size, sub_spacing)
    	sub_pos := [2]f32{
    	g.gs.camera_target.x - sub_size.x * 0.5,
            -242,
        }
		rl.DrawTextEx(g.lcd_font, sub_text, sub_pos, sub_font_size, sub_spacing, PALETTE_4)
	}

	if g.gs.current_level_index == 4 {
		rl.DrawTextureEx(g.danger_texture, [2]f32 {-800, -300}, 0, 0.8, rl.WHITE)
	}

	rl.EndMode2D()

	{ // instructions and ui guide stuff outside of camera
		if g.gs.current_level_index >= 2 {
			hidden_pos :=  [2]f32{
				f32(g.render_texture.texture.width) + 100, 100,
			}
			visible_pos := [2]f32{
				f32(g.render_texture.texture.width) - 150, 100,
			}

			dpad_hidden_pos := hidden_pos
			dpad_hidden_pos.y += 150
			dpad_visible_pos := visible_pos
			dpad_visible_pos.y += 150

			a_visible_pos := visible_pos
			a_hidden_pos := hidden_pos
			a_visible_pos.y += 320
			a_hidden_pos.y += 320

			left_side_hidden_pos := [2]f32 {-300, 0}
			left_side_visible_pos := [2]f32{0, 0}

			right_side_hidden_pos := [2]f32 {f32(g.render_texture.texture.width), 0}
			right_side_visible_pos := [2]f32 {f32(g.render_texture.texture.width)-210, 0}

			top_hidden_pos := [2]f32{0, -200}
			top_visible_pos := [2]f32{0,0}

			bottom_hidden_pos := [2]f32{0, f32(g.render_texture.texture.height)}
			bottom_visible_pos := [2]f32{0, f32(g.render_texture.texture.height) -100}

			hold_tex := g.right_bumper_hold_panel_texture
			release_tex := g.right_bumper_release_panel_texture
			dpad_tex := g.dpad_move_selection_texture
			dpad_crab_walk_tex := g.dpad_crab_walk_texture
			a_select_tex := g.a_button_select_texture
			a_swap_tex := g.a_button_swap_texture

			sandcastle_1_tex := g.sandcastle_deco_1_texture

			p := 1.0 - ((g.gs.zoom_timer / zoom_timer_duration_sec)*(g.gs.zoom_timer / zoom_timer_duration_sec))*(g.gs.zoom_timer / zoom_timer_duration_sec)

			a_p := 1.0 - ((g.gs.swap_selection_change_timer / zoom_timer_duration_sec)*(g.gs.swap_selection_change_timer / zoom_timer_duration_sec))*(g.gs.swap_selection_change_timer / zoom_timer_duration_sec)

			hold_tex_pos := [2]f32{}
			release_tex_pos := [2]f32{}
			dpad_tex_pos := [2]f32 {}
			dpad_crab_walk_tex_pos := [2]f32{}
			a_select_tex_pos := [2]f32{}
			a_swap_tex_pos := [2]f32{}
			sandcastle_1_tex_pos := [2]f32{}
			top_deco_tex_pos := [2]f32{}
			sandcastle_right_tex_pos := [2]f32{}
			bottom_deco_pos := [2]f32{}

			if g.gs.is_rearranging_chunks {
				hold_tex_pos = linalg.lerp(visible_pos, hidden_pos, p)
				dpad_tex_pos = linalg.lerp(dpad_hidden_pos, dpad_visible_pos, p)
				dpad_crab_walk_tex_pos = linalg.lerp(dpad_visible_pos, dpad_hidden_pos, p)

				release_tex_pos = linalg.lerp(hidden_pos, visible_pos, p)

				a_select_tex_pos = linalg.lerp(a_hidden_pos, a_visible_pos, p)

				sandcastle_1_tex_pos = linalg.lerp(left_side_hidden_pos, left_side_visible_pos, p)

				top_deco_tex_pos = linalg.lerp(top_hidden_pos, top_visible_pos, p)

				sandcastle_right_tex_pos = linalg.lerp(right_side_hidden_pos, right_side_visible_pos, p)

				bottom_deco_pos = linalg.lerp(bottom_hidden_pos, bottom_visible_pos, p)

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
				release_tex_pos = linalg.lerp(visible_pos, hidden_pos, p)
				hold_tex_pos = linalg.lerp(hidden_pos, visible_pos, p)

				dpad_tex_pos = linalg.lerp(dpad_visible_pos, dpad_hidden_pos,  p)

				dpad_crab_walk_tex_pos = linalg.lerp(dpad_hidden_pos, dpad_visible_pos, p)

				a_select_tex_pos = linalg.lerp(a_visible_pos, a_hidden_pos, p)

				sandcastle_1_tex_pos = linalg.lerp(left_side_visible_pos, left_side_hidden_pos,  p)

				top_deco_tex_pos = linalg.lerp(top_visible_pos, top_hidden_pos,  p)

				sandcastle_right_tex_pos = linalg.lerp(right_side_visible_pos, right_side_hidden_pos,  p)

				bottom_deco_pos = linalg.lerp(bottom_visible_pos, bottom_hidden_pos,  p)


				if g.gs.is_chunk_selection_active {
					a_swap_tex_pos = linalg.lerp(a_visible_pos, a_hidden_pos, p)
				} else {
					a_swap_tex_pos = a_hidden_pos
				}
			}

			rl.DrawTextureEx(g.bottom_deco_texture, bottom_deco_pos, {}, 1.0, rl.WHITE)
			rl.DrawTextureEx(g.top_deco, top_deco_tex_pos, {}, 1.0, rl.WHITE)
			rl.DrawTextureEx(sandcastle_1_tex, sandcastle_1_tex_pos, {}, 1.0, rl.WHITE)

			rl.DrawTextureEx(g.sandcastle_deco_right_texture, sandcastle_right_tex_pos, {}, 1.0, rl.WHITE)


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

	palete_1_a := PALETTE_1
	palete_1_a.a = 200

	hud_x       : f32 = 8
	hud_y       : f32 = 8
	hud_padding : f32 = 16
	spacing     : f32 = 2

	time_label_font : f32 = 40
	time_value_font : f32 = 72
	level_font      : f32 = 40

	minutes := int(g.gs.elapsed_time) / 60
	seconds := int(g.gs.elapsed_time) % 60
	time_value_text := fmt.ctprintf("%02d:%02d", minutes, seconds)
	level_text      := fmt.ctprintf("Level %d", g.gs.current_level_index + 1)

	time_label_width := rl.MeasureTextEx(g.lcd_font, "TIME", time_label_font, spacing).x
	time_value_width := rl.MeasureTextEx(g.lcd_font, time_value_text, time_value_font, spacing).x
	level_width      := rl.MeasureTextEx(g.lcd_font, level_text, level_font, spacing).x
	content_width    := max(time_label_width, time_value_width, level_width)
	content_height    := time_label_font + time_value_font + level_font

	hud_rect := rl.Rectangle{
		hud_x, hud_y,
		content_width + hud_padding * 2,
		content_height + hud_padding * 2,
	}
	rl.DrawRectangleRounded       (hud_rect, 0.15, 8,    palete_1_a)
	rl.DrawRectangleRoundedLinesEx(hud_rect, 0.15, 8, 3, PALETTE_4)

	text_x       := hud_x + hud_padding
	time_label_y := hud_y + hud_padding
	time_value_y := time_label_y + time_label_font
	level_y      := time_value_y + time_value_font

	rl.DrawTextEx(g.lcd_font, "TIME", {text_x, time_label_y}, time_label_font, spacing, PALETTE_4)
	rl.DrawTextEx(g.lcd_font, time_value_text, {text_x, time_value_y}, time_value_font, spacing, PALETTE_4)
	rl.DrawTextEx(g.lcd_font, level_text, {text_x, level_y}, level_font, spacing, PALETTE_4)

	if g.gs.game_over {
		draw_popup("Racoon got ya", "", "Hit A to play again")
	} else if g.gs.level_complete && g.gs.current_level_index == num_levels - 1 {
		draw_popup(
			"You Win",
			"by Johnny Alfonso and Todd Matthews",
			"Hit A to play again",
			middle2 = "Thank you for playing!",
		)
	} else if g.gs.level_complete {
		time_str := fmt.ctprintf("%02d:%02d", minutes, seconds)
		draw_popup("Level Complete", time_str, "Hit A to continue")
	}

	rl.EndTextureMode()


	if is_in_transition_popup {
		// NOTE(john): putting this at the very bottom,
		// but really it just needs to not affect the camera,
		// because otherwise, for one frame,
		// the camera would be set to the tilemap 0,0
		// and not the crab center
		// IOW, this creates a state where the camera doesn't get centered on the crab properly,
		// and im not sure exactly why,
		// but moving it down here def fixes it for now
		a_pressed := IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) ||
					IsAnyKeysPressed(.ENTER, .SPACE, .Z, .X)
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

		if g.irs.is_recording {
			rl.DrawText("Recording", 10, 10, 20, rl.WHITE)
		}
		if g.irs.is_playback {
			rl.DrawText("Playback", 10, 10, 20, rl.WHITE)
		}

		draw_debug_overlay()

	}
}