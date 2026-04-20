package game


tile_size :: 64
chunk_width :: 5
chunk_height :: 5

tiles_in_chunk :: chunk_width * chunk_height


max_chunks :: 36
max_tiles :: tiles_in_chunk*max_chunks


tile_size_f : f32 : tile_size
chunk_width_f : f32 : chunk_width
chunk_height_f : f32 : chunk_height


// Backing type is explicit i64 so the serialized file format matches across
// platforms (default enum backing is `int`, which is 8 bytes on native but
// 4 bytes on wasm32 — would corrupt reads of the data file on web).
Tile_Type :: enum i64 {
	Trail,
	Solid,
	Key,
	Lock,
	Whatever,
	Flag,
}


Tilemap :: struct {
	tiles : [max_tiles]Tile_Type,
	width : int,
	height : int,
	num_chunks_x : int,
	num_chunks_y : int,
}


Tilemap_Pos :: struct {
	chunk:   [2]int,   // which chunk the entity is in
	rel_pos: [2]f32,   // chunk-local position in tile units, [0, chunk_width) x [0, chunk_height). tile N center at rel_pos = N + 0.5.
}


Tilemap_Tile_Pos :: struct {
	chunk : [2]int,
	tile : [2]int,
}

//////////////////////////////////////////////////////


tilemap_is_coord_in_bounds :: proc(tilemap : ^Tilemap, x, y : int) -> bool {
	in_bounds := x >= 0 && x < tilemap.width &&
		y >= 0 && y < tilemap.height
	return in_bounds
}

tilemap_set_tile :: proc(tilemap : ^Tilemap, x, y : int, val : Tile_Type) {
	in_bounds := tilemap_is_coord_in_bounds(tilemap, x, y)

	if in_bounds {
		tilemap.tiles[(y*tilemap.width)+x] = val
	} else {
		
	}
}

tilemap_get_tile_val ::proc(tilemap :^Tilemap, x, y : int) -> Tile_Type {
	in_bounds := tilemap_is_coord_in_bounds(tilemap, x, y)
	val := Tile_Type.Trail
	if in_bounds {
		val = tilemap.tiles[(y*tilemap.width)+x]
	} else {
	}
	return val
}

set_chunk_tiles_in_tilemap :: proc(tilemap : ^Tilemap, chunk_x, chunk_y : int, tiles:[]Tile_Type) {
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
		num_chunks_y = num_chunks_y,
	}
	return tilemap
}

tilemap_get_chunk_tiles ::proc(tilemap : ^Tilemap, chunk_x, chunk_y : int) -> [tiles_in_chunk]Tile_Type {
	tilemap_chunk := [tiles_in_chunk]Tile_Type{}
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
	return Tile_Type(t.tiles[ty*t.width + tx]) != .Solid &&
		Tile_Type(t.tiles[ty*t.width + tx]) != .Lock
}


chunk_world_origin :: proc(t: ^Tilemap, chunk_x, chunk_y: int) -> [2]f32 {
	o := tilemap_world_origin(t)
	return {
		o.x + f32(chunk_x) * chunk_width_f  * tile_size_f,
		o.y + f32(chunk_y) * chunk_height_f * tile_size_f,
	}
}

tilemap_pos_to_world_pos :: proc(t: ^Tilemap, cp: Tilemap_Pos) -> [2]f32 {
	co := chunk_world_origin(t, cp.chunk.x, cp.chunk.y)
	return {
		co.x + cp.rel_pos.x * tile_size_f,
		co.y + cp.rel_pos.y * tile_size_f,
	}
}

tilemap_pos_absolute_tile :: proc(cp: Tilemap_Pos) -> [2]int {
	return {
		cp.chunk.x * chunk_width  + int(cp.rel_pos.x),
		cp.chunk.y * chunk_height + int(cp.rel_pos.y),
	}
}

absolute_tile_to_tilemap_pos ::proc(tile_x, tile_y :int) -> Tilemap_Pos {
	ret := Tilemap_Pos {
        chunk   = [2]int{tile_x / chunk_width, tile_y / chunk_height},
        rel_pos = [2]f32{
            f32(tile_x % chunk_width)  + 0.5,
            f32(tile_y % chunk_height) + 0.5,
        },
    }
    return ret
}

// Wrap rel_pos into [0, chunk_w) x [0, chunk_h), shifting chunk to compensate.
tilemap_pos_normalize_chunk :: proc(cp: ^Tilemap_Pos) {
	for cp.rel_pos.x >= chunk_width_f  { cp.chunk.x += 1; cp.rel_pos.x -= chunk_width_f  }
	for cp.rel_pos.x < 0               { cp.chunk.x -= 1; cp.rel_pos.x += chunk_width_f  }
	for cp.rel_pos.y >= chunk_height_f { cp.chunk.y += 1; cp.rel_pos.y -= chunk_height_f }
	for cp.rel_pos.y < 0               { cp.chunk.y -= 1; cp.rel_pos.y += chunk_height_f }
}
