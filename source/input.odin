package game

import rl "vendor:raylib"

Input_State :: struct {
	transition_count : int,
	ended_down : bool,
}

Gamepad_State :: struct {
	buttons : [4][rl.GamepadButton]Input_State,
}

All_Input_State :: struct {
	keyboard_keys_state :#sparse [rl.KeyboardKey]Input_State,
	gamepads_state : Gamepad_State,
}


process_key :: proc(key : rl.KeyboardKey) {
	my_key := &g.input_state.keyboard_keys_state[key]

	if rl.IsKeyPressed(key) {
		my_key.ended_down = true
		my_key.transition_count = 1
	} else if rl.IsKeyReleased(key) {
		my_key.ended_down = false
		my_key.transition_count = 1
	}
}


// Aggregate all 4 physical raylib gamepad slots into our virtual slot 0 by
// OR-ing pressed/released events. On web, browsers assign the gamepad to an
// arbitrary slot (often 1, not 0), so the game reads slot 0 regardless of
// where raylib actually sees the device.
process_aggregated_gamepad_button :: proc(btn : rl.GamepadButton) {
	my_gamepad_btn := &g.input_state.gamepads_state.buttons[0][btn]

	pressed, released: bool
	for raw_id in i32(0)..<4 {
		if rl.IsGamepadButtonPressed(raw_id, btn)  do pressed  = true
		if rl.IsGamepadButtonReleased(raw_id, btn) do released = true
	}

	if pressed {
		my_gamepad_btn.ended_down = true
		my_gamepad_btn.transition_count = 1
	} else if released {
		my_gamepad_btn.ended_down = false
		my_gamepad_btn.transition_count = 1
	}
}

update_all_input_state ::proc() {
	g.input_state = g.old_input_state

	for &key_state in g.input_state.keyboard_keys_state {
		key_state.transition_count = 0
	}

	for &pad in g.input_state.gamepads_state.buttons {
	    for &btn_state in pad {
	        btn_state.transition_count = 0
	    }
	}

	for rl_key in rl.KeyboardKey {
		process_key(rl_key)
	}

	for gamepad_btn in rl.GamepadButton {
		process_aggregated_gamepad_button(gamepad_btn)
	}
}

IsKeyPressed :: proc(key : rl.KeyboardKey) -> bool {
	ret := g.input_state.keyboard_keys_state[key].ended_down == true &&
		g.input_state.keyboard_keys_state[key].transition_count > 0
	return ret 
}

IsKeyDown :: proc(key : rl.KeyboardKey) -> bool {
	ret := g.input_state.keyboard_keys_state[key].ended_down == true
	return ret 
}

IsKeyReleased :: proc(key : rl.KeyboardKey) -> bool {
	ret := g.input_state.keyboard_keys_state[key].ended_down == false &&
		g.input_state.keyboard_keys_state[key].transition_count > 0
	return ret 
}

IsKeyUp :: proc(key : rl.KeyboardKey) -> bool {
	ret := !IsKeyDown(key)
	return ret
}


IsGamepadButtonPressed :: proc(gamepad_id : i32, btn : rl.GamepadButton) -> bool {
	state := g.input_state.gamepads_state.buttons[gamepad_id][btn]
	ret := state.ended_down == true && state.transition_count > 0
	return ret
}

IsGamepadButtonDown :: proc(gamepad_id : i32, btn : rl.GamepadButton) -> bool {
	state := g.input_state.gamepads_state.buttons[gamepad_id][btn]
	ret := state.ended_down == true

	return ret
}

IsGamepadButtonReleased :: proc(gamepad_id : i32, btn : rl.GamepadButton) -> bool {
	state := g.input_state.gamepads_state.buttons[gamepad_id][btn]
	ret := state.ended_down == false && state.transition_count > 0
	return ret
}

IsGamepadButtonUp :: proc(gamepad_id : i32, btn : rl.GamepadButton) -> bool {
	ret := !IsGamepadButtonDown(gamepad_id, btn)
	return ret
}