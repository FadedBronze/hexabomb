package log

import "core:os"
import "core:strings"
import "core:time"
import "core:fmt"
import utils "../utils"

LogLevel :: struct {
    handle: os.Handle,
    stdout: bool,
}

FileLogger :: struct {
    handles: map[string]LogLevel,
    directory: string,
    stdout: bool,
}

@(private="file")
_logger: FileLogger

init :: proc(directory: string) {
    buf: [64]u8
    path := utils.concatenate(buf[:], "./logs/", directory, "/")
    err := os.make_directory(path, os.O_CREATE)

    if err != nil && err != .Exist {
        fmt.println(err)
        assert(false)
    }

    _logger.directory = directory
    _logger.handles = make(map[string]LogLevel)
}

clear :: proc(file: string) {
    buf: [64]u8
    path := utils.concatenate(buf[:], "./logs/", _logger.directory, "/", file, ".txt")

    data: [0]u8
    ok := os.write_entire_file(path, data[:])
    assert(ok)
}

@(private="file")
_get_handle :: proc(file: string) -> (ok: bool, level: LogLevel) {
    level, ok = _logger.handles[file]

    if ok {
        return true, level
    }

    buf: [64]u8
    path := utils.concatenate(buf[:], "./logs/", _logger.directory, "/", file, ".txt")

    handle, err := os.open(path, os.O_RDWR | os.O_APPEND | os.O_CREATE)

    level.handle = handle

    switch err {
    case .Permission_Denied, .Invalid_File, .Timeout, .Not_Exist, .Closed:
        fmt.println(err)
        return false, {}
    case nil:
    case:
        fmt.println(err)
        unreachable()
    }
    
    _logger.handles[file] = level

    return true, level
}

set_stdout :: proc(file: string, stdout: bool) -> bool {
    data, ok := _logger.handles[file]
    if !ok {
        ok, data = _get_handle(file)
        if !ok {
            return false
        }
    }
    data.stdout = stdout
    _logger.handles[file] = data
    return true
}

msg :: proc(file: string, data: ..any, loc := #caller_location) {
    t := time.now()

    buffer: [256]u8
    sb := strings.builder_from_slice(buffer[:])

    str := fmt.sbprintln(&sb, "[", t, "](", loc, ") ", data, sep = "")

    ok, level := _get_handle(file)
    
    if level.stdout {
        fmt.println(str)
    }

    if !ok {
        assert(false)
    }

    _, err := os.write_string(level.handle, str)

    switch err {
    case .Permission_Denied, .Timeout, .Not_Exist, .Closed, .Invalid_File:
        fmt.println(str)
        fmt.println(err)
        assert(false)
    case nil:
    case:
        fmt.println(str)
        fmt.println(err)
        unreachable()
    }
}
