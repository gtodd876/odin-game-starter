#+build !wasm32
#+build !wasm64p32

package game

import "core:os"
import "core:mem"
import "core:fmt"

Input_Recording_State :: struct {
    is_recording : bool,
    is_playback : bool,
    recording_file : ^os.File,
    playback_file : ^os.File,
    playback_frame : int,
    slot : int,
}

slot_filenames := [?] string {
    "recording_0",
    "recording_1",
    "recording_2",
    "recording_3",
    "recording_4",
    "recording_5",
    "recording_6",
    "recording_7",
    "recording_8",
    "recording_9",
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



begin_recording_input :: proc(rs : ^Input_Recording_State, s : ^Game_State) {
    filename := slot_filenames[rs.slot]
    file, err := os.open(filename, {.Write, .Create, .Trunc})
    if err != nil {
        fmt.printfln("Error writing recording file: %v", err)
        return
    }

    rs.is_recording = true
    rs.recording_file = file

    bytes_to_write := size_of(s^)
    bytes := mem.byte_slice(s, bytes_to_write)
    bytes_written, write_err := os.write(file, bytes[:])

    if write_err != nil {
        fmt.printfln("Error writing to recording file: %v", write_err)

        rs.is_recording = false
        os.close(rs.recording_file)
        rs.recording_file = nil

        return
    }

    if bytes_written != bytes_to_write {
        fmt.printfln("Failed to write entire game memory to file")

        rs.is_recording = false
        os.close(rs.recording_file)
        rs.recording_file = nil

        return
    }

}


record_input :: proc(rs : ^Input_Recording_State, new_input : ^All_Input_State) {
    new_input_bytes := mem.byte_slice(new_input, size_of(new_input^))
    _, err := os.write(rs.recording_file, new_input_bytes)
    if err != nil {
        fmt.printfln("error recording input. Turning off recording")
        end_recording_input(rs)
    }
}


end_recording_input :: proc(rs : ^Input_Recording_State) {
    os.close(rs.recording_file)
    rs.is_recording = false
}


begin_input_playback :: proc(rs : ^Input_Recording_State, s : ^Game_State) {
    filename := slot_filenames[rs.slot]
    file, file_open_err := os.open(filename)

    if file_open_err != nil {
        fmt.printfln("Error opening recording file: %v", file_open_err)
        return
    }

    bytes_to_read := size_of(s^)
    gmem_bytes := mem.byte_slice(s, bytes_to_read)
    bytes_read, read_err := os.read(file, gmem_bytes)

    if read_err != nil {
        fmt.printfln("Error reading game memory")
        return
    } else if bytes_read != bytes_to_read {
        fmt.printfln("Failed to read entire game memory from recording file")
        return
    }

    rs.playback_frame = 0
    rs.is_recording = false
    rs.recording_file = nil
    rs.is_playback = true
    rs.playback_file = file
}


playback_input :: proc(rs : ^Input_Recording_State, s : ^Game_State, game_input : ^All_Input_State) {
    nbytes_to_read := size_of(game_input^)
    game_input_bytes := mem.byte_slice(game_input, nbytes_to_read)
    nbytes_read, file_read_err := os.read(rs.playback_file, game_input_bytes)

    rs.playback_frame += 1
    
    reached_end_of_file := nbytes_read == 0
    
    if reached_end_of_file {
        rs.playback_frame = 0
        end_input_playback(rs)
        begin_input_playback(rs, s)
        os.read(rs.playback_file, game_input_bytes)
    } else if nbytes_read != nbytes_to_read {
        fmt.printfln("Was not able to read all of game controller input. ending playback")
        rs.is_playback = false
        os.close(rs.playback_file)
        return
    } else if file_read_err != nil {
        fmt.printfln("error reading game controller input. ending playback: %v", file_read_err)
        rs.is_playback = false
        os.close(rs.playback_file)
        return
    }
}

end_input_playback :: proc(rs : ^Input_Recording_State) {
    os.close(rs.playback_file)
    rs.is_playback = false
}