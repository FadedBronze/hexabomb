package main

import rl "vendor:raylib"
import "utils"

Audio :: struct {
    handles: map[string]rl.Music,
    basepath: string,
}

@(private="file")
audio: ^Audio

init_audio :: proc(basepath: string, audio_ptr: ^Audio) {
    assert(audio_ptr != nil)
    audio = audio_ptr
    audio.handles = make(map[string]rl.Music)
    audio.basepath = basepath

    load_sfx(audio, "explosion.mp3", 0.125)
    load_sfx(audio, "music.mp3", 0.3, true)
    load_sfx(audio, "click.mp3", 0.3)
}

load_sfx :: proc(audio: ^Audio, sound: string, volume: f32, looping := false) {
    buf: [32]u8
    path: cstring = transmute(cstring)raw_data(utils.concatenate(buf[:], audio.basepath, sound, "\x00"))
    music := rl.LoadMusicStream(path)
    rl.SetMusicVolume(music, volume)
    music.looping = looping
    audio.handles[sound] = music
}

play_audio :: proc(sound: string) -> bool {
    handle, ok := audio.handles[sound]
    if !ok { return false }

    rl.PlayMusicStream(handle)

    return true
}

update_audio :: proc() {
    for _, handle in audio.handles {
        rl.UpdateMusicStream(handle)
    }
}
