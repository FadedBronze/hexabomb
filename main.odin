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

Visibility :: enum {
  Visible,
  Invisible,
}

Tile :: struct {
  playerIndex: u32,
  position: [2]i8,
  visibility: Visibility,
  type: TileType,
}

TileGrid :: struct {
  tiles: [128]Tile,
  tileCount: i32,
  hexagonSize: i32,
  offset: [2]i32,
  size: i8,
}

fill_hexagon :: proc(centerX: i32, centerY: i32, r: i32, color: rl.Color) {
  radius := i32(f32(r) * 1.05)+1
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

render_gameboard :: proc(game: ^Game) {
  tileGrid := &game.tileGrid

  size: i32 = tileGrid.hexagonSize
  half_length := f32(size) * math.sqrt_f32(3) / 3

  for i in i8(-15)..<i8(15) {
    for j in i8(-15)..<i8(15) {
      if abs(i) % 2 != abs(j) % 2 {
        continue;
      }

      if within_halfgrid_range(tileGrid.size, {i, j}) {
        fill_hexagon_halfgrid(la.Vector2f32{f32(i), f32(j)}, tileGrid.offset, rl.Color{0, 20, 128, 255}, tileGrid.hexagonSize)
      }
    }
  }


  for tile in tileGrid.tiles {
      player := &game.players[tile.playerIndex]
      fill_hexagon_halfgrid(la.Vector2f32{f32(tile.position.x), f32(tile.position.y)}, tileGrid.offset, player.color, tileGrid.hexagonSize)
  }
}

get_halfgrid_pos_unoffset :: proc(pos: la.Vector2f32, size: i32) -> la.Vector2f32 {
  half_length := f32(size) * math.sqrt_f32(3) / 3
  half_size := f32(size) / 2

  halfgrid := la.Vector2f32{pos.x / half_length, pos.y / half_size}
  halfgrid.x /= 3 
  halfgrid.y /= 2

  halfgrid.x = math.floor_f32(halfgrid.x)
  halfgrid.y = math.floor_f32(halfgrid.y)

  if i32(abs(halfgrid.x)) % 2 != i32(abs(halfgrid.y)) % 2 {
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

get_halfgrid_pos :: proc(pos: la.Vector2f32, size: i32) -> la.Vector2f32 {
  offset := la.Vector2f32{0, 0}
  gridpos := get_halfgrid_pos_unoffset(pos + offset, size) - get_halfgrid_pos_unoffset(offset, size)
  return gridpos
}

fill_hexagon_halfgrid :: proc(halfgrid: la.Vector2f32, offset: [2]i32, color: rl.Color, size: i32) {
  half_length := f32(size) * math.sqrt_f32(3) / 3
  fill_hexagon(i32((halfgrid.x + 0.5) * half_length * 3) + offset.x, i32((halfgrid.y + 1) * f32(size)) + offset.y, size, color)
}

outline_hexagon_halfgrid :: proc(halfgrid: la.Vector2f32, offset: [2]i32, color: rl.Color, size: i32) {
  half_length := f32(size) * math.sqrt_f32(3) / 3
  outline_hexagon(i32((halfgrid.x + 0.5) * half_length * 3) + offset.x, i32((halfgrid.y + 1) * f32(size)) + offset.y, size, color)
}

within_halfgrid_range :: proc(size: i8, pos: [2]i8) -> bool {
  return abs(pos.x) + size/2 < size && abs(pos.y) < size && abs(pos.x) + abs(pos.y) < size;
}

Game :: struct {
  currentPlayerIndex: u32,
  players: [4]Player,
  playerCount: u32,
  tileGrid: TileGrid,
  screenSize: [2]i32,
}

Player :: struct {
  color: rl.Color,
  selectedTileType: TileType,
}

init_game :: proc(game: ^Game) {
  game.currentPlayerIndex = 0

  game.playerCount = 2
  game.players[0] = Player {
    color = rl.BLUE,
  }
  game.players[1] = Player {
    color = rl.RED,
  }

  game.screenSize = {800, 600}

  game.tileGrid = TileGrid {
    tiles = {},
    size = 8,
    hexagonSize = 30
  }
  
  half_length := i32(f32(game.tileGrid.hexagonSize) * math.sqrt_f32(3) / 3)
  size := game.tileGrid.hexagonSize

  game.tileGrid.offset = {game.screenSize.x / 2 - half_length, game.screenSize.y / 2 - size}
}

hover_tilegrid :: proc(tileGrid: ^TileGrid, player: ^Player) {
  pos := rl.GetMousePosition() - la.Vector2f32{f32(tileGrid.offset.x), f32(tileGrid.offset.y)}
  halfgrid := get_halfgrid_pos(pos, tileGrid.hexagonSize)

  if (within_halfgrid_range(tileGrid.size, {i8(halfgrid.x), i8(halfgrid.y)})) {
    fill_hexagon_halfgrid(halfgrid, tileGrid.offset, player.color, tileGrid.hexagonSize)
  } else {
    outline_hexagon_halfgrid(halfgrid, tileGrid.offset, rl.RED, tileGrid.hexagonSize)
  }
}

update_game :: proc(game: ^Game, dt: f32) {
    player := &game.players[game.currentPlayerIndex]
    halfgridPos := get_halfgrid_pos(rl.GetMousePosition() - la.Vector2f32{f32(game.tileGrid.offset.x), f32(game.tileGrid.offset.y)}, game.tileGrid.hexagonSize)

    render_gameboard(game)
    hover_tilegrid(&game.tileGrid, player)

    if rl.IsMouseButtonPressed(.LEFT) {
      tile := &game.tileGrid.tiles[game.tileGrid.tileCount]

      fmt.println(halfgridPos)

      tile.playerIndex = game.currentPlayerIndex

      tile.position = {i8(halfgridPos.x), i8(halfgridPos.y)} 
      tile.visibility = .Invisible
      tile.type = player.selectedTileType

      game.tileGrid.tileCount += 1
      game.currentPlayerIndex += 1
      game.currentPlayerIndex %= game.playerCount
    }
}

main :: proc() {
  game: Game
  init_game(&game)
  
  rl.InitWindow(game.screenSize.x, game.screenSize.y, "hexabomb")

  for !rl.WindowShouldClose() {
    rl.BeginDrawing()
    rl.ClearBackground(rl.WHITE)

    update_game(&game, rl.GetFrameTime())

    rl.EndDrawing()
  }
}
