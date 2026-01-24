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
  Cannon,
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
  shotIds: [4]u32, 
  type: TileType,
}

Cannon :: struct {
  direction: HexDirection,
}

TileGrid :: struct {
  activeTileId: u32,
  tiles: [MAX_GRID_SIZE * MAX_GRID_SIZE]Tile,
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

MAX_SHOTS :: 16

Shot :: struct {
  playerIndex: u32,
  cannonPos: HalfGridPosition,
  targetDir: HexDirection,
}

Game :: struct {
  shots: [MAX_SHOTS]Shot,
  shot_count: u32,
  currentPlayerIndex: u32,
  players: [4]Player,
  playerCount: u32,
  tileGrid: TileGrid,
  ui: UI,
}

get_tile :: proc(tileGrid: ^TileGrid, pos: HalfGridPosition) -> ^Tile {
  idx := (pos.y + HALF_MAX_GRID_SIZE) * MAX_GRID_SIZE + (pos.x + HALF_MAX_GRID_SIZE)
  return &tileGrid.tiles[idx]
}

init_tilegrid :: proc(tileGrid: ^TileGrid, ui: ^UI) {
  hexagonSize: i32 = 30

  tileGrid^ = TileGrid {
    size = 8,
    hexagonSize = hexagonSize,
    activeTileId = 0,
  }

  update_tilegrid_offset(tileGrid)
  
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

update_tilegrid_offset :: proc(tileGrid: ^TileGrid) {
  half_length := i32(f32(tileGrid.hexagonSize) * math.sqrt_f32(3) / 3)
  tileGrid.offset = {rl.GetScreenWidth() / 2 - half_length, rl.GetScreenHeight() / 2 - tileGrid.hexagonSize}
}

init_game :: proc(game: ^Game) {
  game^ = Game {
    currentPlayerIndex = 0,
    playerCount = 2,
  }

  game.players[0] = Player {
    color = rl.BLUE,
    username = "Blue",
    selectedTileType = .Land,
  }

  game.players[1] = Player {
    color = rl.RED,
    username = "Red",
    selectedTileType = .Land,
  }
  
  //game.players[2] = Player {
  //  color = rl.GREEN,
  //  username = "Green",
  //  selectedTileType = .Land,
  //}

  init_tilegrid(&game.tileGrid, &game.ui)

  start_next_turn(game)
}

update_game :: proc(game: ^Game, dt: f32) {
    player := &game.players[game.currentPlayerIndex]
 
    update_tilegrid_offset(&game.tileGrid)
    render_gameboard(game)
    
    switch player.editMode {
      case .Placing:
        place_tile(game)
      case .Clicking:
        click_tile(game)
    }

    hover_tilegrid(&game.tileGrid, player, &game.ui)
}

get_tile_id :: proc(pos: HalfGridPosition) -> u32 {
  return u32((pos.y + HALF_MAX_GRID_SIZE) * MAX_GRID_SIZE + (pos.x + HALF_MAX_GRID_SIZE)) + 1
}

get_active_tile :: proc(tilegrid: ^TileGrid) -> (^Tile, HalfGridPosition) {
  if tilegrid.activeTileId == 0 {
    return nil, {}
  }
  idx := tilegrid.activeTileId-1

  fmt.println(idx)

  x := idx % MAX_GRID_SIZE
  y := idx / MAX_GRID_SIZE

  return &tilegrid.tiles[idx], HalfGridPosition{i16(x)-HALF_MAX_GRID_SIZE, i16(y)-HALF_MAX_GRID_SIZE}
}

hover_tilegrid :: proc(tileGrid: ^TileGrid, player: ^Player, ui: ^UI, id := #caller_location) {
  if ui.activeId == empty_id() {
    ui.activeId = id
  }
  if ui.activeId != id {
    return
  }

  halfgrid := get_tile_grid_pos(tileGrid, rl.GetMousePosition())

  if player.editMode == .Clicking {
      if tileGrid.activeTileId != 0 {
        return
      }

      fill_hexagon_halfgrid(halfgrid, tileGrid.offset, rl.Color{255, 255, 255, 50}, tileGrid.hexagonSize)
      return;
  }

  if (within_halfgrid_range(tileGrid.size, {i16(halfgrid.x), i16(halfgrid.y)})) {
    switch player.selectedTileType {
    case .BlastTarget:
      spos := get_screen_position(tileGrid, halfgrid)
      rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{255, 0, 0, 255})
      rl.DrawCircle(i32(spos.x), i32(spos.y), 10, rl.Color{255, 255, 255, 255})
      rl.DrawCircle(i32(spos.x), i32(spos.y), 5, rl.Color{255, 0, 0, 255})
    case .Land:
      fill_hexagon_halfgrid(halfgrid, tileGrid.offset, player.color, tileGrid.hexagonSize)
    case .Cannon:
      spos := get_screen_position(tileGrid, halfgrid)
      rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{200, 200, 200, 255})
    case .Shield:
      spos := get_screen_position(tileGrid, halfgrid)
      fill_hexagon(i32(spos.x), i32(spos.y), 20, rl.Color{200, 200, 200, 255})
    case .Free:
    case .Blocked:
    }
  } else {
    outline_hexagon_halfgrid(halfgrid, tileGrid.offset, rl.RED, tileGrid.hexagonSize)
  }
}

click_tile :: proc(game: ^Game) {
  halfgrid := get_tile_grid_pos(&game.tileGrid, rl.GetMousePosition())
  hovered_tile := get_tile(&game.tileGrid, halfgrid)

  player := &game.players[game.currentPlayerIndex]

  if rl.IsMouseButtonPressed(.LEFT) {
    fmt.println(hovered_tile)

    if hovered_tile.type == .Cannon {
      game.tileGrid.activeTileId = get_tile_id(halfgrid)
      
      player.editMode = .Placing
      player.selectedTileType = .BlastTarget
    }
  }
}

EditMode :: enum {
  Placing,
  Clicking,
}

Player :: struct {
  color: rl.Color,
  selectedTileType: TileType,
  editMode: EditMode,
  energy: u16,
  username: cstring,
}

next_to :: proc(a: HalfGridPosition, b: HalfGridPosition) -> (bool, HexDirection) {
  for point, i in directions {
    if a + point == b {
      return true, HexDirection(i)
    }
  }
  return false, HexDirection(0)
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

    if tile.type != .Free && tile.type != .Blocked && tile.type != .BlastTarget {
      fill_hexagon_halfgrid(pos, tileGrid.offset, player.color, tileGrid.hexagonSize)

      if (game.currentPlayerIndex == tile.playerIndex) {
        if tile.type == .Cannon {
          spos := get_screen_position(&game.tileGrid, pos)
          rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{200, 200, 200, 255})
        }
        
        if tile.type == .Shield {
          spos := get_screen_position(&game.tileGrid, pos)
          fill_hexagon(i32(spos.x), i32(spos.y), 20, rl.Color{200, 200, 200, 255})
        }

      }
    }

    for shotId in tile.shotIds {
      if shotId != 0 && game.shots[shotId-1].playerIndex == game.currentPlayerIndex {
        spos := get_screen_position(&game.tileGrid, pos)
        rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{255, 0, 0, 125})
        rl.DrawCircle(i32(spos.x), i32(spos.y), 10, rl.Color{255, 255, 255, 125})
        rl.DrawCircle(i32(spos.x), i32(spos.y), 5, rl.Color{255, 0, 0, 125})
      }
    }
  }
}

append_shotId :: proc(tile: ^Tile, shotId: u32) {
  for i in 0..<len(tile.shotIds) {
    id := &tile.shotIds[i]
    if id^ == 0 {
      id^ = shotId
      return
    }
  }
}

place_tile :: proc(game: ^Game) {
  player := &game.players[game.currentPlayerIndex]
  halfgridPos := get_tile_grid_pos(&game.tileGrid, rl.GetMousePosition())
  tile := get_tile(&game.tileGrid, halfgridPos)

  if !rl.IsMouseButtonPressed(.LEFT) {
    return
  }

  cannon, cannonHalfgridPos := get_active_tile(&game.tileGrid)
  hit, dir := next_to(halfgridPos, cannonHalfgridPos)
  
  if player.selectedTileType == .BlastTarget && hit {
    append_shotId(tile, game.shot_count+1)

    game.shots[game.shot_count] = Shot {
      cannonPos = cannonHalfgridPos,
      playerIndex = game.currentPlayerIndex,
      targetDir = dir,
    }

    game.tileGrid.activeTileId = 0
    player.editMode = .Clicking
    
    game.shot_count += 1
  } else {
    if player.selectedTileType != .Land && (tile.type != .Land || tile.playerIndex != game.currentPlayerIndex) {
      return 
    }

    next_to_own_territory :: proc(game: ^Game, tile: ^Tile) -> bool {
      player := &game.players[game.currentPlayerIndex]
      return tile.playerIndex == game.currentPlayerIndex && tile.type != .Blocked && tile.type != .Free
    }

    if !test_adjacent_cell(game, halfgridPos, next_to_own_territory) {
      return
    } 
  }
  
  req_energy := tileTypeCost[player.selectedTileType]

  if req_energy > player.energy {
    return
  }

  player.energy -= req_energy
  tile.visibility = .Invisible
  
  if player.selectedTileType != .BlastTarget {
    tile.playerIndex = game.currentPlayerIndex
    tile.type = player.selectedTileType
  }
}

start_next_turn :: proc (game: ^Game) {
  game.currentPlayerIndex += 1

  if game.currentPlayerIndex == game.playerCount {
    game.currentPlayerIndex = 0

    end_turn(game)
  }

  player := &game.players[game.currentPlayerIndex]
  player.energy = 3
}

end_turn :: proc (game: ^Game) {

}

ui_layout :: proc(game: ^Game) {
  ui := &game.ui
  // ui buttonstrip
  row_layout(ui, .Right, {10, 10}, 10)
  
  player := &game.players[game.currentPlayerIndex]

  if (button(ui, rl.Rectangle {
    width = 100,
    height = 75,
  }, "cannon", player.color)) {
    player.selectedTileType = .Cannon
    player.editMode = .Placing
  }
  
  if (button(ui, rl.Rectangle {
    width = 100,
    height = 75,
  }, "land", player.color)) {
    player.selectedTileType = .Land
    player.editMode = .Placing
  }
  
  if (button(ui, rl.Rectangle {
    width = 100,
    height = 75,
  }, "shield", player.color)) {
    player.selectedTileType = .Shield
    player.editMode = .Placing
  }

  if (button(ui, rl.Rectangle {
    width = 100,
    height = 75,
  }, "click", player.color)) {
    player.editMode = .Clicking
  }

  row_layout_end(ui)
  
  row_layout(ui, .Left, {f32(rl.GetScreenWidth()-10), f32(rl.GetScreenHeight()-10) - 75}, 10)
  
  if (button(ui, rl.Rectangle {
    width = 150,
    height = 75,
  }, "end turn", player.color)) {
    start_next_turn(game)
  }
 
  text_display(ui, rl.Rectangle {
    width = 100,
    height = 75,
  }, player.username, player.color)

  row_layout_end(ui)
}

main :: proc() {
  game: Game
  init_game(&game)
  
  rl.InitWindow(800, 800, "hexabomb")
  rl.SetWindowState({.WINDOW_RESIZABLE})

  for !rl.WindowShouldClose() {
    rl.BeginDrawing()
    rl.ClearBackground(rl.WHITE)

    update_game(&game, rl.GetFrameTime())
    ui_layout(&game)

    rl.EndDrawing()
  }
}
