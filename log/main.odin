package log

import "core:os"
import "core:strings"
import "core:time"
import "core:fmt"

FileLogger :: struct {
    handles: map[string]os.Handle,
    directory: string,
}

@(private="file")
_logger: FileLogger

init :: proc(directory: string) {
    err := os.make_directory(strings.concatenate({"./logs/", directory, "/"}), os.O_CREATE)

    if err != nil && err != .Exist {
        fmt.println(err)
        assert(false)
    }

    _logger.directory = directory
    _logger.handles = make(map[string]os.Handle)
}

clear :: proc(file: string) {
    data: [0]u8
    path := strings.concatenate({"./logs/", _logger.directory, "/", file, ".txt"})
    ok := os.write_entire_file(path, data[:])
    assert(ok)
}

@(private="file")
_get_handle :: proc(file: string) -> (ok: bool, handle: os.Handle) {
    handle, ok = _logger.handles[file]

    if ok {
        return true, handle
    }

    path := strings.concatenate({"./logs/", _logger.directory, "/", file, ".txt"})
    err: os.Error
    handle, err = os.open(path, os.O_RDWR | os.O_APPEND | os.O_CREATE)

    switch err {
    case .Permission_Denied, .Invalid_File, .Timeout, .Not_Exist, .Closed:
        fmt.println(err)
        return false, {}
    case nil:
    case:
        fmt.println(err)
        unreachable()
    }
    
    _logger.handles[file] = handle

    return true, handle
}

msg :: proc(file: string, data: ..any, loc := #caller_location) {
    t := time.now()

    sb: strings.Builder
    _, sberr := strings.builder_init(&sb)

    if sberr != nil {
        fmt.println(sberr)
        assert(false)
    }
    
    ok, handle := _get_handle(file)

    if !ok {
        assert(false)
    }

    str := fmt.sbprintln(&sb, "[", t, "](", loc, ") ", data, sep = "")
    _, err := os.write_string(handle, str)

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
