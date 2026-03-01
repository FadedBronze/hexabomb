package utils
import rl "vendor:raylib"

concatenate :: proc(buf: []u8, strs: ..string) -> string {
    offset := 0
    for str in strs {
        copy_from_string(buf[offset:offset+len(str)], str)
        offset += len(str)
    }
    return transmute(string)buf[0:offset]
}

blend_two_colors :: proc(b: rl.Color, a: rl.Color, t: f32) -> rl.Color {
    rr := (f32(a.r) - f32(b.r)) * t + f32(b.r)
    gg := (f32(a.g) - f32(b.g)) * t + f32(b.g)
    bb := (f32(a.b) - f32(b.b)) * t + f32(b.b)
    aa := (f32(a.a) - f32(b.a)) * t + f32(b.a)

    return rl.Color{u8(rr), u8(gg), u8(bb), u8(aa)}
}

blend_colors :: proc(colors: []rl.Color, t: f32) -> rl.Color {
    assert(len(colors)>0)

    if len(colors) == 1 {
        return colors[0]
    }

    t := t
    if t == 1 {
        t = 0.999
    }

    curr := t * f32(len(colors)-1)

    colorIdxDown: int = int(curr)
    colorIdxUp: int = int(curr)+1

    t = (curr - f32(colorIdxDown)) / f32(len(colors))

    return blend_two_colors(colors[colorIdxDown], colors[colorIdxUp], t)
}
