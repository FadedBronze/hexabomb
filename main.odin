package main

import "core:fmt"
import rl "vendor:raylib"
import "core:math"
import la "core:math/linalg"

TileType :: enum {
  Blocked,
  Free,
  Land,
  Canon,
}

Tile :: struct {
  playerIndex: u32,
  position: [2]i8,
  visibility: bool,
}

TileGrid :: struct {
  tiles: [128]Tile,
  size: i8,
}

fill_hexagon :: proc(centerX: i32, centerY: i32, r: i32, color: rl.Color) {
  radius := r + 1
  half_length := i32(f64(radius) * math.sqrt_f64(3) / 3)

  rl.DrawRectangle(centerX - half_length, centerY - radius, 2 * half_length, radius * 2, color)
  rl.DrawTriangle(
    la.Vector2f32{auto_cast (centerX - half_length), auto_cast (centerY - radius)}, 
    la.Vector2f32{auto_cast (centerX - half_length * 2), auto_cast centerY},
    la.Vector2f32{auto_cast (centerX - half_length), auto_cast centerY},
    color,
  )
  rl.DrawTriangle(
    la.Vector2f32{auto_cast (centerX - half_length * 2), auto_cast centerY},
    la.Vector2f32{auto_cast (centerX - half_length), auto_cast (centerY + radius)}, 
    la.Vector2f32{auto_cast (centerX - half_length), auto_cast centerY},
    color,
  )
  rl.DrawTriangle(
    la.Vector2f32{auto_cast (centerX + half_length * 2), auto_cast centerY},
    la.Vector2f32{auto_cast (centerX + half_length), auto_cast (centerY - radius)}, 
    la.Vector2f32{auto_cast (centerX + half_length), auto_cast centerY},
    color,
  )
  rl.DrawTriangle(
    la.Vector2f32{auto_cast (centerX + half_length), auto_cast (centerY + radius)}, 
    la.Vector2f32{auto_cast (centerX + half_length * 2), auto_cast centerY},
    la.Vector2f32{auto_cast (centerX + half_length), auto_cast centerY},
    color,
  )

}

outline_hexagon :: proc(centerX: i32, centerY: i32, radius: i32, color: rl.Color) {
  half_length := i32(f64(radius) * math.sqrt_f64(3) / 3)

  points := [7]la.Vector2f32{
    la.Vector2f32{auto_cast (centerX + half_length), auto_cast (centerY + radius)},
    la.Vector2f32{auto_cast (centerX - half_length), auto_cast (centerY + radius)}, 
    la.Vector2f32{auto_cast (centerX - 2*half_length), auto_cast (centerY)}, 
    la.Vector2f32{auto_cast (centerX - half_length), auto_cast (centerY - radius)}, 
    la.Vector2f32{auto_cast (centerX + half_length), auto_cast (centerY - radius)}, 
    la.Vector2f32{auto_cast (centerX + 2*half_length), auto_cast (centerY)},
    la.Vector2f32{auto_cast (centerX + half_length), auto_cast (centerY + radius)},
  }

  rl.DrawLineStrip(raw_data(&points), 7, color)
}

render_tilegrid :: proc(tiles: ^TileGrid, offset: [2]i8) {
  size: i32 = 20
  half_length := f32(size) * math.sqrt_f32(3) / 3

  for i in i8(0)..<i8(20) {
    for j in i8(0)..<i8(20) {
      if i % 2 != j % 2 {
        continue;
      }

      if within_halfgrid_range(tiles.size, offset, {i, j}) {
        fill_hexagon_halfgrid(la.Vector2f32{f32(i), f32(j)}, rl.Color{0, 20, 128, 255})
      }
    }
  }
}

get_halfgrid_pos :: proc(pos: la.Vector2f32, size: i32) -> la.Vector2f32 {
  half_length := f32(size) * math.sqrt_f32(3) / 3
  half_size := f32(size) / 2

  halfgrid := la.Vector2f32{pos.x / half_length, pos.y / half_size}
  halfgrid.x /= 3 
  halfgrid.y /= 2

  halfgrid.x = math.trunc_f32(halfgrid.x)
  halfgrid.y = math.trunc_f32(halfgrid.y)

  if i32(halfgrid.x) % 2 != i32(halfgrid.y) % 2 {
    a := la.Vector2f32{halfgrid.x + 1, halfgrid.y}
    b := la.Vector2f32{halfgrid.x, halfgrid.y + 1}
    c := la.Vector2f32{halfgrid.x - 1, halfgrid.y}
    d := la.Vector2f32{halfgrid.x, halfgrid.y - 1}

    if la.vector_length(halfgrid - a) < la.vector_length(halfgrid - b) {
      halfgrid = a
    }

    if la.vector_length(halfgrid - b) < la.vector_length(halfgrid - c) {
      halfgrid = b
    }

    if la.vector_length(halfgrid - c) < la.vector_length(halfgrid - d) {
      halfgrid = c 
    } else {
      halfgrid = d
    }
  }

  return halfgrid
}

fill_hexagon_halfgrid :: proc(halfgrid: la.Vector2f32, color: rl.Color) {
  size: i32 = 20

  half_length := f32(size) * math.sqrt_f32(3) / 3
  fill_hexagon(i32((halfgrid.x + 0.5) * half_length * 3), i32((halfgrid.y + 1) * f32(size)), size, color)
}

outline_hexagon_halfgrid :: proc(halfgrid: la.Vector2f32, color: rl.Color) {
  size: i32 = 20

  half_length := f32(size) * math.sqrt_f32(3) / 3
  outline_hexagon(i32((halfgrid.x + 0.5) * half_length * 3), i32((halfgrid.y + 1) * f32(size)), size, color)
}

hover_tilegrid :: proc() {
  size: i32 = 20

  half_length := f32(size) * math.sqrt_f32(3) / 3
  half_size := f32(size) / 2

  pos := rl.GetMousePosition()
  halfgrid := get_halfgrid_pos(pos, size)

  if (within_halfgrid_range(8, {10, 10}, {i8(halfgrid.x), i8(halfgrid.y)})) {
    fill_hexagon_halfgrid(halfgrid, rl.BLUE)
  } else {
    //outline_hexagon_halfgrid(halfgrid, rl.BLACK)
  }
}

within_halfgrid_range :: proc(size: i8, shift: [2]i8, posi: [2]i8) -> bool {
  pos := posi - shift

  return abs(pos.x) + size/2 < size && abs(pos.y) < size && abs(pos.x) + abs(pos.y) < size;
}

main :: proc() {
  rl.InitWindow(800, 600, "hexabomb")

  tileGrid: TileGrid = {
    tiles = {},
    size = 8,
  }

  for !rl.WindowShouldClose() {
    rl.BeginDrawing()
    rl.ClearBackground(rl.WHITE)

    render_tilegrid(&tileGrid, {10, 10})
    hover_tilegrid()

    rl.EndDrawing()
  }
}
