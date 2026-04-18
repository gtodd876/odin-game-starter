package game

// NOTE(johnb) only reason putting in here is i found i often
// want to just see update stuff in one pane,
// and anything else in the other pane at the same time

import rl "vendor:raylib"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:os"


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

	save_button := rl.KeyboardKey.F12
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

	load_button := rl.KeyboardKey.F11
	if rl.IsKeyPressed(load_button) {
		t_load_data(context.temp_allocator)
	}

	if g.debug.paused do return

	// NOTE(john) cause camera got centered at 0,0
	arrangement_pos := [2]f32{-1280/2,-720/2}

	{ // editor stuff
		mouse_screen := rl.GetMousePosition()
		mouse_world := rl.GetScreenToWorld2D(mouse_screen, game_camera())
		mouse_rel_tilemap := mouse_world - arrangement_pos
		if (rl.IsMouseButtonPressed(.LEFT)) {
			tile_x := int(mouse_rel_tilemap.x) / tile_size
			tile_y := int(mouse_rel_tilemap.y) / tile_size
			tile_val := tilemap_get_tile_val(tilemap, tile_x, tile_y)
			if tile_val == 1 {
				 tilemap_set_tile(tilemap, tile_x, tile_y, 0)
			} else if tile_val == 0 {
				 tilemap_set_tile(tilemap, tile_x, tile_y, 1)				
			}
		}
	}

	if IsKeyPressed(.UP) || IsKeyPressed(.W) {
		g.gs.hovered_chunk.y -= 1
	}
	if IsKeyPressed(.DOWN) || IsKeyPressed(.S) {
		g.gs.hovered_chunk.y += 1

	}
	if IsKeyPressed(.LEFT) || IsKeyPressed(.A) {
		g.gs.hovered_chunk.x -= 1

	}
	if IsKeyPressed(.RIGHT) || IsKeyPressed(.D) {
		g.gs.hovered_chunk.x += 1
	}

	if IsKeyPressed(.SPACE) {
		if g.gs.is_chunk_selection_active {
			hovered_tiles := tilemap_get_chunk_tiles(tilemap,
				g.gs.hovered_chunk.x, g.gs.hovered_chunk.y)
			selected_tiles := tilemap_get_chunk_tiles(tilemap,
				g.gs.selected_chunk.x, g.gs.selected_chunk.y)

			set_chunk_tiles_in_tilemap(tilemap, g.gs.hovered_chunk.x, g.gs.hovered_chunk.y, selected_tiles[:])
			set_chunk_tiles_in_tilemap(tilemap, g.gs.selected_chunk.x, g.gs.selected_chunk.y, hovered_tiles[:])
			g.gs.is_chunk_selection_active = false
		} else {
			g.gs.is_chunk_selection_active = true
			g.gs.selected_chunk = g.gs.hovered_chunk
		}
	}

	// NOTE(john) make sure selection stays within the bounds
	// of the overall chunk arrangemetn
	g.gs.hovered_chunk.x %%= tilemap.num_chunks_x
	g.gs.hovered_chunk.y %%= tilemap.num_chunks_y



	// g.gs.player_pos += input * rl.GetFrameTime() * g.debug.player_speed


	rl.BeginTextureMode(g.render_texture)
	rl.ClearBackground(PALETTE_1)

	rl.BeginMode2D(game_camera())


	// NOTE(john) cause camera got centered at 0,0

	for chunk_x in 0..<tilemap.num_chunks_x {
		for chunk_y in 0..<tilemap.num_chunks_y {
			tilemap_chunk := tilemap_get_chunk_tiles(tilemap, chunk_x, chunk_y)
			chunk_pos := [2]f32{
				arrangement_pos.x + (tile_size_f*chunk_width_f*f32(chunk_x)),
				arrangement_pos.y + (tile_size_f*chunk_width_f*f32(chunk_y)),
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
			color.a = 100

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

		// draw_debug_overlay()

	}
}