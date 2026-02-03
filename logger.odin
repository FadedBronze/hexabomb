package main

import "core:os"
import "core:strings"
import "core:time"
import "core:fmt"

FileLogger :: struct {
  handle: os.Handle,
  path: string,
}

init_log :: proc(errorLog: ^FileLogger, path: string, clear_file: bool) -> (ok:bool) {
  if clear_file {
    wrhandle, err2 := os.open(path, os.O_TRUNC | os.O_CREATE)
    os.close(wrhandle)
    
    if err2 != nil {
      fmt.println(err2)
      assert(false)
    }
  }

  handle, err := os.open(path, os.O_APPEND | os.O_CREATE)

  switch err {
  case .Permission_Denied, .Timeout, .Not_Exist, .Closed:
    fmt.println(err)
    return false
  case nil:
  case:
    fmt.println(err)
    unreachable()
  }

  errorLog^ = FileLogger {
    handle = handle,
    path = path,
  }

  return true
}

log_msg :: proc(logger: ^FileLogger, data: ..any, loc := #caller_location) -> (ok:bool) {
  buf: [256]u8

  t := time.now()

  sb := strings.builder_from_slice(buf[:])
  str := fmt.sbprintln(&sb, "[", t, "](", loc, ") ", data, sep = "")

  _, err := os.write_string(logger.handle, str)

  switch err {
  case .Permission_Denied, .Timeout, .Not_Exist, .Closed, .Invalid_File:
    fmt.println(str)
    fmt.println(err)
    return false
  case nil:
  case:
    fmt.println(str)
    fmt.println(err)
    unreachable()
  }
  return true
}
