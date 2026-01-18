package main

import "core:fmt"
import rl "vendor:raylib"
import "core:math"
import la "core:math/linalg"

tileTypeCost := []u16{
  0, 
  0,
  1,
  3,
  3,
}

TileType :: enum {
  Blocked,
  Free,
  Land,
  Canon,
  Shield,
}

Visibility :: enum {
  Visible,
  Invisible,
}

HalfGridPosition :: [2]i16

Tile :: struct {
  playerIndex: u32,
  visibility: Visibility,
  type: TileType,
}

TileGrid :: struct {
  tiles: [1024]Tile,
  hexagonSize: i32,
  offset: [2]i32,
  size: i16,
}

// -------------------------------------- HALFGRID ------------------------------------ //

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

get_tile_grid_pos :: proc(tileGrid: ^TileGrid, position: la.Vector2f32) -> HalfGridPosition {
  grid_pos := get_halfgrid_pos(rl.GetMousePosition() - la.Vector2f32{f32(tileGrid.offset.x), f32(tileGrid.offset.y)}, tileGrid.hexagonSize)
  return { i16(grid_pos.x), i16(grid_pos.y) }
}

// -------------------------------------- HALFGRID ------------------------------------ //

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

  for i in i16(-15)..<i16(15) {
    for j in i16(-15)..<i16(15) {
      if abs(i) % 2 != abs(j) % 2 {
        continue;
      }

      if within_halfgrid_range(tileGrid.size, {i, j}) {
        fill_hexagon_halfgrid({i, j}, tileGrid.offset, rl.Color{0, 20, 128, 255}, tileGrid.hexagonSize)
      }
    }
  }

  for tile, i in tileGrid.tiles {
    i := i16(i)

    pos: HalfGridPosition = {(i % 32) - 16, (i / 32) - 16}

    player := &game.players[tile.playerIndex]

    if tile.type == .Land {
      fill_hexagon_halfgrid(pos, tileGrid.offset, player.color, tileGrid.hexagonSize)
    }
  }
}

fill_hexagon_halfgrid :: proc(halfgridPos: HalfGridPosition, offset: [2]i32, color: rl.Color, size: i32) {
  half_length := f32(size) * math.sqrt_f32(3) / 3
  fill_hexagon(i32((f32(halfgridPos.x) + 0.5) * half_length * 3) + offset.x, i32((f32(halfgridPos.y) + 1) * f32(size)) + offset.y, size, color)
}

outline_hexagon_halfgrid :: proc(halfgridPos: HalfGridPosition, offset: [2]i32, color: rl.Color, size: i32) {
  half_length := f32(size) * math.sqrt_f32(3) / 3
  outline_hexagon(i32((f32(halfgridPos.x) + 0.5) * half_length * 3) + offset.x, i32((f32(halfgridPos.y) + 1) * f32(size)) + offset.y, size, color)
}

within_halfgrid_range :: proc(size: i16, pos: [2]i16) -> bool {
  return abs(pos.x) + size/2 < size && abs(pos.y) < size && abs(pos.x) + abs(pos.y) < size;
}

Game :: struct {
  currentPlayerIndex: u32,
  players: [4]Player,
  playerCount: u32,
  tileGrid: TileGrid,
  screenSize: [2]i32,
}

get_tile :: proc(tileGrid: ^TileGrid, pos: HalfGridPosition) -> ^Tile {
  idx := (pos.y + 16) * 32 + (pos.x + 16)
  fmt.println(idx)
  return &tileGrid.tiles[idx]
}

init_game :: proc(game: ^Game) {
  game.currentPlayerIndex = 0

  game.playerCount = 2

  game.players[0] = Player {
    color = rl.BLUE,
    selectedTileType = .Land,
  }

  game.players[1] = Player {
    color = rl.RED,
    selectedTileType = .Land,
  }

  game.screenSize = {800, 600}

  game.tileGrid = TileGrid {
    size = 8,
    hexagonSize = 30
  }

  get_tile(&game.tileGrid, {3, 3})^ = Tile {
    playerIndex = 0,
    type = .Land,
  }
  
  get_tile(&game.tileGrid, {-3, -3})^ = Tile {
    playerIndex = 1,
    type = .Land,
  }
  
  half_length := i32(f32(game.tileGrid.hexagonSize) * math.sqrt_f32(3) / 3)
  size := game.tileGrid.hexagonSize

  game.tileGrid.offset = {game.screenSize.x / 2 - half_length, game.screenSize.y / 2 - size}
}

update_game :: proc(game: ^Game, dt: f32) {
    player := &game.players[game.currentPlayerIndex]

    render_gameboard(game)
    hover_tilegrid(&game.tileGrid, player)

    if rl.IsKeyPressed(.ONE) {
      player.selectedTileType = .Land
    }
    
    if rl.IsKeyPressed(.TWO) {
      player.selectedTileType = .Canon
    }
    
    if rl.IsKeyPressed(.THREE) {
      player.selectedTileType = .Shield
    }

    if rl.IsKeyPressed(.N) {
      start_turn(game)
    }

    place_tile(game)
}

Player :: struct {
  color: rl.Color,
  selectedTileType: TileType,
  energy: u16,
}

start_turn :: proc (game: ^Game) {
  game.currentPlayerIndex += 1
  game.currentPlayerIndex %= game.playerCount

  player := &game.players[game.currentPlayerIndex]
  player.energy = 3
}

hover_tilegrid :: proc(tileGrid: ^TileGrid, player: ^Player) {
  halfgrid := get_tile_grid_pos(tileGrid, rl.GetMousePosition())

  if (within_halfgrid_range(tileGrid.size, {i16(halfgrid.x), i16(halfgrid.y)})) {
    fill_hexagon_halfgrid(halfgrid, tileGrid.offset, player.color, tileGrid.hexagonSize)
  } else {
    outline_hexagon_halfgrid(halfgrid, tileGrid.offset, rl.RED, tileGrid.hexagonSize)
  }
}

place_tile :: proc(game: ^Game) {
  player := &game.players[game.currentPlayerIndex]
  halfgridPos := get_tile_grid_pos(&game.tileGrid, rl.GetMousePosition())

  if !rl.IsMouseButtonPressed(.LEFT) {
    return
  }

  req_energy := tileTypeCost[player.selectedTileType]

  if req_energy >= player.energy {
    return
  }

  player.energy -= req_energy

  tile := get_tile(&game.tileGrid, halfgridPos)

  tile.playerIndex = game.currentPlayerIndex
  tile.visibility = .Invisible
  tile.type = player.selectedTileType
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
