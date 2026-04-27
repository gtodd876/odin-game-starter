package game

import rl "vendor:raylib"
import "core:strings"
import "core:strconv"

update_dev_console :: proc(screen_width, screen_height : f32) {
	if g.dev_console.show {
		text_field_rec := rl.Rectangle {0, screen_height - 30, screen_width, 30}
		black_a := rl.Color{0,0,0,200}
		rl.DrawRectangleRec(text_field_rec, black_a)
		
		Key_Char :: struct {
			key : rl.KeyboardKey,
			char : u8,
		}

		key_to_char := [?]Key_Char {
		    {.A, 'a'},
		    {.B, 'b'},
		    {.C, 'c'},
		    {.D, 'd'},
		    {.E, 'e'},
		    {.F, 'f'},
		    {.G, 'g'},
		    {.H, 'h'},
		    {.I, 'i'},
		    {.J, 'j'},
		    {.K, 'k'},
		    {.L, 'l'},
		    {.M, 'm'},
		    {.N, 'n'},
		    {.O, 'o'},
		    {.P, 'p'},
		    {.Q, 'q'},
		    {.R, 'r'},
		    {.S, 's'},
		    {.T, 't'},
		    {.U, 'u'},
		    {.V, 'v'},
		    {.W, 'w'},
		    {.X, 'x'},
		    {.Y, 'y'},
		    {.Z, 'z'},
		    {.ZERO,  '0'},
		    {.ONE,   '1'},
		    {.TWO,   '2'},
		    {.THREE, '3'},
		    {.FOUR,  '4'},
		    {.FIVE,  '5'},
		    {.SIX,   '6'},
		    {.SEVEN, '7'},
		    {.EIGHT, '8'},
		    {.NINE,  '9'},
		    {.SPACE, ' '},
		}

		get_char :: proc(key_to_char : []Key_Char, key : rl.KeyboardKey) -> (c : u8) {
			c = 0
			for kc in key_to_char {
				if kc.key == key {
					c = kc.char
				}
			}
			return c
		} 

		for key in rl.KeyboardKey {
			pressed := ( rl.IsKeyPressedRepeat(key) || rl.IsKeyPressed(key) ) &&
				!rl.IsKeyDown(.LEFT_CONTROL) 
			if pressed {
				c := get_char(key_to_char[:], key)
				if c != 0 {
					append(&g.dev_console.buffer, c)
				}
				backspace_pressed := key == rl.KeyboardKey.BACKSPACE
				can_backspace := len(g.dev_console.buffer) > 0
				if can_backspace && backspace_pressed {
					g.dev_console.buffer[len(g.dev_console.buffer) - 1] = 0
					pop(&g.dev_console.buffer)
				}
			}	
		}

		buffer_cstring : cstring = ""
		if len(g.dev_console.buffer) > 0 {
			buffer_cstring = cstring(&g.dev_console.buffer[0])
		}


		rl.DrawText(buffer_cstring, i32(text_field_rec.x), i32(text_field_rec.y), 24, rl.WHITE)

		submit_command := rl.IsKeyPressed(.ENTER)
		if submit_command {
			raw_string_text_input := strings.clone_from_bytes(g.dev_console.buffer[:], context.temp_allocator)
			parts : [dynamic; 100]string
			// TODO(john) this currently dont work if there are multiple spaces
			// between command line words
			
			for s in strings.split_by_byte_iterator(&raw_string_text_input, ' ') {
				part := strings.trim_space(s)
				append(&parts, part)
			}
			if len(parts) > 0 {
				cmd := parts[0]
				if cmd == "level" {
					if len(parts) > 1 {
						sub_cmd := parts[1]
						if sub_cmd == "swap" {
							if len(parts) > 2 {
								arg := parts[2]
								num, ok := strconv.parse_int(arg, 10)
								if ok {
									swap_levels(num, g.gs.current_level_index)
									change_level_and_initialize(g.gs.current_level_index)
								}
							}
						}
						else if sub_cmd == "goto" {
							if len(parts) > 2 {
								arg := parts[2]
								num, ok := strconv.parse_int(arg, 10)
								if ok {
									change_level_and_initialize(num)
								}
							}
						}
						else if sub_cmd == "new" {
							if len(parts) > 3 {
								arg_chunks_x := parts[2]
								arg_chunks_y := parts[3]
								chunks_x, ok_x := strconv.parse_int(arg_chunks_x, 10)
								chunks_y, ok_y := strconv.parse_int(arg_chunks_y, 10)
								both_ok := ok_x && ok_y
								if both_ok {
									new_level := Level{}
									new_level.tilemap = init_tilemap_by_specifying_chunks(chunks_x, chunks_y)
									append(&g.level_pack.levels, new_level)
								}
							}
						}
					}
				}
			}
			g.dev_console.buffer = {}
			clear(&g.dev_console.buffer)
		}
	}

	toggle_dev_console := rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.T)
	if toggle_dev_console {
		g.dev_console.show = !g.dev_console.show
	}
	
}
