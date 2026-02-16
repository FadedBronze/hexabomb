package utils

concatenate :: proc "contextless" (buf: []u8, strs: ..string) -> string {
    offset := 0
    for str in strs {
        copy_from_string(buf[offset:offset+len(str)], str)
        offset += len(str)
    }
    return transmute(string)buf[0:offset]
}
