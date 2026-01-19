package main

import "core:fmt"
import rl "vendor:raylib"
import "core:math"
import la "core:math/linalg"

MAX_GRID_SIZE :: 32 
HALF_MAX_GRID_SIZE :: MAX_GRID_SIZE / 2

tileTypeCost := []u16{
  0, 
  0,
  1,
  2,
  1,
  1,
}
  
directions := [][2]i16 {
  {0, 2},
  {0, -2},
  {-1, 1},
  {-1, -1},
  {1, 1},
  {1, -1},
}

HexDirection :: enum {
  Up,
  Down,
  LeftUp,
  LeftDown,
  RightUp,
  RightDown,
}

TileType :: enum {
  Blocked,
  Free,
  Land,
  Canon,
  Shield,
  BlastTarget,
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
  tileData: TileData,
}

NotSpecial :: struct {}

Canon :: struct {
  direction: HexDirection,
  ui_id: u32,
}

TileData :: union {
  Canon,
}

TileGrid :: struct {
  tiles: [MAX_GRID_SIZE * MAX_GRID_SIZE]Tile,
  hexagonSize: i32,
  offset: [2]i32,
  size: i16,
  placeTilesId: u32,
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

get_screen_position :: proc(tileGrid: ^TileGrid, halfgridPos: HalfGridPosition) -> la.Vector2f32 {
  half_length := f32(tileGrid.hexagonSize) * math.sqrt_f32(3) / 3
  return la.Vector2f32{
    (f32(halfgridPos.x) + 0.5) * half_length * 3 + f32(tileGrid.offset.x), 
    (f32(halfgridPos.y) + 1) * f32(tileGrid.hexagonSize) + f32(tileGrid.offset.y)
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

Shot :: struct {
  cannonPos: HalfGridPosition,
  targetPos: HalfGridPosition,
}

Game :: struct {
  currentPlayerIndex: u32,
  players: [4]Player,
  playerCount: u32,
  tileGrid: TileGrid,
  screenSize: [2]i32,
  ui: UI,
}

get_tile :: proc(tileGrid: ^TileGrid, pos: HalfGridPosition) -> ^Tile {
  idx := (pos.y + HALF_MAX_GRID_SIZE) * MAX_GRID_SIZE + (pos.x + HALF_MAX_GRID_SIZE)
  return &tileGrid.tiles[idx]
}

init_tilegrid :: proc(tileGrid: ^TileGrid, ui: ^UI, screenSize: [2]i32) {
  hexagonSize: i32 = 30

  tileGrid.placeTilesId = reserve_ids(ui, 10)

  half_length := i32(f32(hexagonSize) * math.sqrt_f32(3) / 3)

  tileGrid^ = TileGrid {
    size = 8,
    hexagonSize = hexagonSize,
    offset = {screenSize.x / 2 - half_length, screenSize.y / 2 - hexagonSize}
  }
  
  get_tile(tileGrid, {3, 3})^ = Tile {
    playerIndex = 0,
    type = .Land,
    visibility = .Invisible,
  }
  
  get_tile(tileGrid, {-3, -3})^ = Tile {
    playerIndex = 1,
    type = .Land,
    visibility = .Invisible,
  }
}

init_game :: proc(game: ^Game) {
  game^ = Game {
    currentPlayerIndex = 0,
    playerCount = 2,
    screenSize = {800, 600}
  }

  game.players[0] = Player {
    color = rl.BLUE,
    selectedTileType = .Land,
  }

  game.players[1] = Player {
    color = rl.RED,
    selectedTileType = .Land,
  }

  init_tilegrid(&game.tileGrid, &game.ui, game.screenSize)

  start_turn(game)
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
    
    if rl.IsKeyPressed(.FOUR) {
      player.selectedTileType = .BlastTarget
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

hover_tilegrid :: proc(tileGrid: ^TileGrid, player: ^Player) {
  halfgrid := get_tile_grid_pos(tileGrid, rl.GetMousePosition())

  if (within_halfgrid_range(tileGrid.size, {i16(halfgrid.x), i16(halfgrid.y)})) {
    if player.selectedTileType == .Land {
      fill_hexagon_halfgrid(halfgrid, tileGrid.offset, player.color, tileGrid.hexagonSize)
    }

    if player.selectedTileType == .Canon {
      spos := get_screen_position(tileGrid, halfgrid)
      rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{200, 200, 200, 255})
    }
    
    if player.selectedTileType == .Shield {
      spos := get_screen_position(tileGrid, halfgrid)
      fill_hexagon(i32(spos.x), i32(spos.y), 20, rl.Color{200, 200, 200, 255})
    }
    
    if player.selectedTileType == .BlastTarget {
      spos := get_screen_position(tileGrid, halfgrid)
      rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{255, 0, 0, 255})
      rl.DrawCircle(i32(spos.x), i32(spos.y), 10, rl.Color{255, 255, 255, 255})
      rl.DrawCircle(i32(spos.x), i32(spos.y), 5, rl.Color{255, 0, 0, 255})
    }
  } else {
    outline_hexagon_halfgrid(halfgrid, tileGrid.offset, rl.RED, tileGrid.hexagonSize)
  }
}

test_adjacent_cell :: proc(game: ^Game, p: HalfGridPosition, test: proc(game: ^Game, tile: ^Tile) -> bool) -> bool {
  for point in directions {
    if test(game, get_tile(&game.tileGrid, point + p)) {
      return true;
    }
  }

  return false;
}

render_gameboard :: proc(game: ^Game) {
  tileGrid := &game.tileGrid

  size: i32 = tileGrid.hexagonSize
  half_length := f32(size) * math.sqrt_f32(3) / 3

  for i in i16(-HALF_MAX_GRID_SIZE)..<i16(HALF_MAX_GRID_SIZE) {
    for j in i16(-HALF_MAX_GRID_SIZE)..<i16(HALF_MAX_GRID_SIZE) {
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

    pos: HalfGridPosition = {(i % MAX_GRID_SIZE) - HALF_MAX_GRID_SIZE, (i / MAX_GRID_SIZE) - HALF_MAX_GRID_SIZE}
    player := &game.players[tile.playerIndex]

    if tile.type != .Free && tile.type != .Blocked {
      if tile.type != .BlastTarget {
        fill_hexagon_halfgrid(pos, tileGrid.offset, player.color, tileGrid.hexagonSize)
      }

      if (game.currentPlayerIndex == tile.playerIndex) {
        if tile.type == .Canon {
          spos := get_screen_position(&game.tileGrid, pos)
          rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{200, 200, 200, 255})
        }
        
        if tile.type == .Shield {
          spos := get_screen_position(&game.tileGrid, pos)
          fill_hexagon(i32(spos.x), i32(spos.y), 20, rl.Color{200, 200, 200, 255})
        }

        if tile.type == .BlastTarget {
          spos := get_screen_position(&game.tileGrid, pos)
          rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{255, 0, 0, 255})
          rl.DrawCircle(i32(spos.x), i32(spos.y), 10, rl.Color{255, 255, 255, 255})
          rl.DrawCircle(i32(spos.x), i32(spos.y), 5, rl.Color{255, 0, 0, 255})
        }
      }
    }
  }
}

place_tile :: proc(game: ^Game) {
  player := &game.players[game.currentPlayerIndex]
  halfgridPos := get_tile_grid_pos(&game.tileGrid, rl.GetMousePosition())

  if !rl.IsMouseButtonPressed(.LEFT) {
    return
  }

  test :: proc(game: ^Game, tile: ^Tile) -> bool {
    player := &game.players[game.currentPlayerIndex]

    if player.selectedTileType == .BlastTarget {
      return tile.playerIndex == game.currentPlayerIndex && tile.type == .Canon
    } 

    if player.selectedTileType == .Land {
      return tile.playerIndex == game.currentPlayerIndex && tile.type == .Land
    }

    return true
  }

  if !test_adjacent_cell(game, halfgridPos, test) {
    return
  }
  
  req_energy := tileTypeCost[player.selectedTileType]

  if req_energy > player.energy {
    return
  }

  tile := get_tile(&game.tileGrid, halfgridPos)

  if player.selectedTileType != .BlastTarget && player.selectedTileType != .Land && (tile.type != .Land || tile.playerIndex != game.currentPlayerIndex) {
    return 
  }

  player.energy -= req_energy
  tile.playerIndex = game.currentPlayerIndex
  tile.visibility = .Invisible
  tile.type = player.selectedTileType
}

start_turn :: proc (game: ^Game) {
  game.currentPlayerIndex += 1
  game.currentPlayerIndex %= game.playerCount

  player := &game.players[game.currentPlayerIndex]
  player.energy = 3
}

end_turn :: proc (game: ^Game) {
}

UI :: struct {
  nextFreeId: u32,
  activeId: u32,
}

reserve_ids :: proc(ui: ^UI, count: u32) -> u32 {
  nextFreeId := ui.nextFreeId
  ui.nextFreeId += count
  return nextFreeId
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
