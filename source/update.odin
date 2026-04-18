package game

// NOTE(johnb) only reason putting in here is i found i often
// want to just see update stuff in one pane,
// and anything else in the other pane at the same time

import rl "vendor:raylib"

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


update :: proc() {

	// NOTE(john): these are ints in here only because its easy to write in code
	// These are planned to be enum values once
	//... if we have an actual editor where we are placing these things
	tilemap_chunk00 := Tilemap_Chunk{
		tiles = {
			1,1,1,1,1,
			1,0,0,0,0,
			1,0,1,1,1,
			1,0,1,1,1,
			1,0,1,1,1,
		}
	}
	tilemap_chunk01 := Tilemap_Chunk{
		tiles = {
			1,0,1,1,1,
			1,0,1,1,1,
			1,0,0,0,0,
			1,0,1,1,1,
			1,0,1,1,1,
		}
	}
	tilemap_chunk02 := Tilemap_Chunk{
		tiles = {
			1,1,1,1,1,
			1,1,1,1,1,
			0,0,0,0,0,
			1,1,1,1,1,
			1,1,1,1,1,
		}
	}
	tilemap_chunk03 := Tilemap_Chunk{
		tiles = {
			1,1,1,1,1,
			1,0,1,1,1,
			0,0,1,1,1,
			1,0,1,1,1,
			1,0,1,1,1,
		}
	}

	chunk_arrangement := Chunk_Arrangement {}
	chunk_arrangement.chunks[0] = tilemap_chunk00
	chunk_arrangement.chunks[1] = tilemap_chunk01
	chunk_arrangement.chunks[2] = tilemap_chunk02
	chunk_arrangement.chunks[3] = tilemap_chunk03
	chunk_arrangement.width = 2
	chunk_arrangement.height = 2



	if rl.IsKeyPressed(.F3) do g.debug.show_overlay = !g.debug.show_overlay
	if rl.IsKeyPressed(.F4) do g.debug.paused = !g.debug.paused

	if rl.IsKeyPressed(.ESCAPE) {
		g.run = false
	}

	if g.debug.paused do return

	input: rl.Vector2

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

	// NOTE(john) make sure selection stays within the bounds
	// of the overall chunk arrangemetn
	g.gs.hovered_chunk.x %%= chunk_arrangement.width
	g.gs.hovered_chunk.y %%= chunk_arrangement.height



	g.gs.player_pos += input * rl.GetFrameTime() * g.debug.player_speed


	rl.BeginTextureMode(g.render_texture)
	rl.ClearBackground(rl.BLUE)

	rl.BeginMode2D(game_camera())


	// NOTE(john) cause camera got centered at 0,0
	arrangement_pos := [2]f32{-1280/2,-720/2}


	for chunk_x in 0..<chunk_arrangement.width {
		for chunk_y in 0..<chunk_arrangement.height {
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

			tilemap_chunk := chunk_arrangement.chunks[(chunk_y*chunk_arrangement.width)+(chunk_x)]

			for tile_x in 0..<chunk_width {
				for tile_y in 0..<chunk_height {
					i := tile_y*chunk_width + tile_x
					tile_type := tilemap_chunk.tiles[i]
					color := Tile_Type(tile_type) == .Solid ? rl.BLACK : rl.WHITE
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
			t_yellow := rl.YELLOW
			t_yellow.a = 100

			// Note(john) using term chunk id to refer to the 2D index
			// which can really be thought of as an integer coordinate 
			// system
			chunk_id := [2]int{chunk_x, chunk_y}
			if chunk_id == g.gs.hovered_chunk {
				t_yellow.a = 255
			}

			rl.DrawRectangleLinesEx(chunk_rect, 2, t_yellow)
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
		
		draw_debug_overlay()

	}
}