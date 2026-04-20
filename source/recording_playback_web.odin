#+build wasm32, wasm64p32

package game

Input_Recording_State :: struct {
    is_recording : bool,
    is_playback  : bool,
}

cycle_record_playback :: proc() {}

record_input :: proc(rs : ^Input_Recording_State, new_input : ^All_Input_State) {}

playback_input :: proc(rs : ^Input_Recording_State, s : ^Game_State, game_input : ^All_Input_State) {}
