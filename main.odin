package main

import "core:strconv"
import "core:fmt"
import rl "vendor:raylib"
import "core:math"
import la "core:math/linalg"

MAX_GRID_SIZE :: 32 
CANNONBALL_SPEED :: 4
HALF_MAX_GRID_SIZE :: MAX_GRID_SIZE / 2
MAX_PLAYERS :: 4

directions := [][2]i16 {
  {0, 2},
  {1, 1},
  {1, -1},
  {0, -2},
  {-1, -1},
  {-1, 1},
}

directionHexnormalized := [][2]f32 {
  {0, 1},
  {math.sqrt_f32(3)/2, 0.5},
  {math.sqrt_f32(3)/2, -0.5},
  {0, -1},
  {-math.sqrt_f32(3)/2, -0.5},
  {-math.sqrt_f32(3)/2, 0.5},
}

HexDirection :: enum {
  Up,
  RightUp,
  RightDown,
  Down,
  LeftDown,
  LeftUp,
}

TileType :: enum {
  Free,
  Blocked,
  Land,
  Cannon,
  Shield,
  BlastTarget,
  Nuke,
  Mortar,
  MortarTarget,
  Telescope,
}

Visibility :: [MAX_PLAYERS]enum {
  Invisible,
  Visible,
  VeryVisible,
}

HalfGridPosition :: [2]i16

Tile :: struct {
  playerIndex: u8,
  visibility: Visibility,
  entityIds: [8]u32, 
  type: TileType,
  durability: u8,
  damage: u8,
  direction: HexDirection,
}

Cannon :: struct {
  direction: HexDirection,
}

TileGrid :: struct {
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
  grid_pos := get_halfgrid_pos(position - la.Vector2f32{f32(tileGrid.offset.x), f32(tileGrid.offset.y)}, tileGrid.hexagonSize)
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

MAX_ENTITIES :: 32

Shot :: struct {
  position: la.Vector2f32,
  velocity: la.Vector2f32,
}

EntityType :: enum {
  Nuke,
  Shot,
  MortarShot,
}

SimulationEntity :: struct {
  type: EntityType,
  completed: bool,
  playerIndex: u8,
  halfgridPos: HalfGridPosition,
  damage: u8,
  using shot: Shot,
}

GameState :: enum {
  GameSelector,
  Playing,
  Simulate,
  Winner,
  Paused,
}

PlayerState :: enum {
  Done,
  Playing,
}

Player :: struct {
  playerState: PlayerState,
  color: rl.Color,
  selectedTileType: TileType,
  editMode: EditMode,
  energy: u16,
  username: string,
  activeTileId: u32,
  inputState: ^InputState,
  virtual: bool,
}

TileTypeStat :: struct {
  scaling: u8,
  scalingCost: u8,
  damage: u8,
  cost: u8,
  durability: u8,
}

//NOT APPLICABLE
NA := max(u8)

defaultTileTypeStats := [TileType]TileTypeStat{
  .Free = {NA, NA, NA, NA, 0}, 
  .Blocked = {NA, NA, NA, NA, 0},
  .Land = {NA, NA, NA, 1, 0},
  .Cannon = {NA, NA, NA, 1, 0},
  .Shield = {1, 1, NA, 0, 1},
  .BlastTarget = {NA, NA, NA, 1, 0},
  .Nuke = {NA, NA, 1, 3, 0},
  .Mortar = {1, 2, 1, 1, 0},
  .MortarTarget = {NA, NA, NA, 1, 0},
  .Telescope = {NA, NA, NA, 1, 0},
}

GameStats :: struct {
  energyPerRound: u16,
}

defaultGameStats := GameStats{
  energyPerRound = 3,
}

Game :: struct {
  ui: UI,

  tileTypeStats: [TileType]TileTypeStat,
  stats: GameStats,

  state: GameState,
  order: bool,
  rounds: u32,

  playerCount: u8,
  players: [MAX_PLAYERS]Player,
  winnerIdx: u8,

  tileGrid: TileGrid,
  entities: [MAX_ENTITIES]SimulationEntity,
  entity_count: u32,
  completed_entities: u32,
}

get_tile :: proc(tileGrid: ^TileGrid, pos: HalfGridPosition) -> ^Tile {
  idx := (pos.y + HALF_MAX_GRID_SIZE) * MAX_GRID_SIZE + (pos.x + HALF_MAX_GRID_SIZE)
  return &tileGrid.tiles[idx]
}

update_tilegrid_offset :: proc(tileGrid: ^TileGrid, inputState: ^InputState) {
  half_length := i32(f32(tileGrid.hexagonSize) * math.sqrt_f32(3) / 3)
  tileGrid.offset = {i32(inputState.screenSize.x) / 2 - half_length, i32(inputState.screenSize.y) / 2 - tileGrid.hexagonSize}
}

playerColors := [4]rl.Color {
  rl.BLUE,
  rl.RED,
  rl.GREEN,
  rl.ORANGE,
}

get_tile_id :: proc(pos: HalfGridPosition) -> u32 {
  return u32((pos.y + HALF_MAX_GRID_SIZE) * MAX_GRID_SIZE + (pos.x + HALF_MAX_GRID_SIZE)) + 1
}

get_active_tile :: proc(tilegrid: ^TileGrid, player: ^Player) -> (^Tile, HalfGridPosition) {
  if player.activeTileId == 0 {
    return nil, {}
  }
  idx := player.activeTileId-1

  x := idx % MAX_GRID_SIZE
  y := idx / MAX_GRID_SIZE

  return &tilegrid.tiles[idx], HalfGridPosition{i16(x)-HALF_MAX_GRID_SIZE, i16(y)-HALF_MAX_GRID_SIZE}
}

hover_tilegrid :: proc(tileGrid: ^TileGrid, inputState: ^InputState, player: ^Player, ui: ^UI, virtual: bool, id := #caller_location) {
  if ui.activeId == empty_id() {
    ui.activeId = id
  }
  
  if virtual {
    return
  }

  if ui.activeId != id {
    return
  }

  halfgrid := get_tile_grid_pos(tileGrid, inputState.mousePos)

  if player.editMode == .Clicking {
      if player.activeTileId != 0 {
        return
      }

      fill_hexagon_halfgrid(halfgrid, tileGrid.offset, rl.Color{255, 255, 255, 50}, tileGrid.hexagonSize)
      return;
  }

  if (within_halfgrid_range(tileGrid.size, {i16(halfgrid.x), i16(halfgrid.y)})) {
    spos := get_screen_position(tileGrid, halfgrid)

    switch player.selectedTileType {
    case .Nuke:
      rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{255, 0, 0, 255})
      rl.DrawCircle(i32(spos.x), i32(spos.y), 10, rl.Color{255, 255, 255, 255})
      rl.DrawCircle(i32(spos.x), i32(spos.y), 5, rl.Color{255, 0, 0, 255})
    case .BlastTarget:
      rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{255, 0, 0, 255})
      rl.DrawCircle(i32(spos.x), i32(spos.y), 10, rl.Color{255, 255, 255, 255})
      rl.DrawCircle(i32(spos.x), i32(spos.y), 5, rl.Color{255, 0, 0, 255})
    case .Land:
      fill_hexagon_halfgrid(halfgrid, tileGrid.offset, player.color, tileGrid.hexagonSize)
    case .Cannon:
      rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{200, 200, 200, 255})
    case .Shield:
      fill_hexagon(i32(spos.x), i32(spos.y), 20, rl.Color{200, 200, 200, 255})
    case .Free:
    case .Blocked:
    case .Mortar:
      rl.DrawCircle(i32(spos.x)+5, i32(spos.y), 10, rl.Color{200, 200, 200, 255})
      rl.DrawCircle(i32(spos.x), i32(spos.y)+5, 10, rl.Color{200, 200, 200, 255})
      rl.DrawCircle(i32(spos.x)+2, i32(spos.y)+2, 10, rl.Color{200, 200, 200, 255})
    case .MortarTarget:
      rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{255, 0, 0, 255})
      rl.DrawCircle(i32(spos.x), i32(spos.y), 10, rl.Color{255, 255, 255, 255})
      rl.DrawCircle(i32(spos.x), i32(spos.y), 5, rl.Color{255, 0, 0, 255})
    case .Telescope:
      rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{255, 255, 0, 255})
      rl.DrawCircle(i32(spos.x), i32(spos.y), 18, rl.Color{255, 255, 255, 255})
    }
  } else {
    outline_hexagon_halfgrid(halfgrid, tileGrid.offset, rl.RED, tileGrid.hexagonSize)
  }
}

format_cost_and_scaling :: proc(game: ^Game, tileType: TileType, buf: []u8) -> string {
  scalingCost := game.tileTypeStats[tileType].scalingCost
  scaling := game.tileTypeStats[tileType].scaling

  buf[0] = '+'
  str := strconv.itoa(buf[1:], int(scaling))
  copy(buf[len(str)+1:len(str)+1+6], " for -")
  str2 := strconv.itoa(buf[len(str)+1+6:], int(scalingCost))
  copy(buf[len(str)+len(str2)+1+6:], "e")

  return cast(string)buf[0:len(str)+len(str2)+1+6+1]
}

click_tile :: proc(game: ^Game, inputState: ^InputState, currentPlayerIndex: u8) {
  halfgrid := get_tile_grid_pos(&game.tileGrid, inputState.mousePos)
  hovered_tile := get_tile(&game.tileGrid, halfgrid)

  player := &game.players[currentPlayerIndex]

  if inputState.leftButton == .Pressed {
    if hovered_tile.type == .Cannon && hovered_tile.playerIndex == currentPlayerIndex {
      player.activeTileId = get_tile_id(halfgrid)
      
      player.editMode = .Placing
      player.selectedTileType = .BlastTarget
    }
    
    if hovered_tile.type == .Shield && hovered_tile.playerIndex == currentPlayerIndex {
      player.activeTileId = get_tile_id(halfgrid)
    }
    
    if hovered_tile.type == .Mortar && hovered_tile.playerIndex == currentPlayerIndex {
      player.activeTileId = get_tile_id(halfgrid)
    }
  }

  tile, pos := get_active_tile(&game.tileGrid, player)
  
  if tile != nil && tile.type == .Mortar {
    row_layout(&game.ui, .Down, la.Vector2f32{inputState.screenSize.x - 10 - 150, inputState.screenSize.y / 2 - 52.5}, 5)

    buf: [32]u8

    if (button(&game.ui, inputState, rl.Rectangle {
      width = 150,
      height = 50,
    }, format_cost_and_scaling(game, .Mortar, buf[:]), player.color) && player.energy >= auto_cast game.tileTypeStats[.Mortar].scalingCost) {
      tile.damage += game.tileTypeStats[.Mortar].scaling
      player.energy -= auto_cast game.tileTypeStats[.Mortar].scalingCost
    }
    
    if (button(&game.ui, inputState, rl.Rectangle {
      width = 150,
      height = 50,
    }, "fire", player.color)) {
      player.editMode = .Placing
      player.selectedTileType = .MortarTarget
    }
    
    row_layout_end(&game.ui)
  }

  if tile != nil && tile.type == .Shield {
    row_layout(&game.ui, .Down, la.Vector2f32{f32(rl.GetScreenWidth()) - 10 - 150, f32(rl.GetScreenHeight()) / 2 - 52.5}, 5)

    buf: [32]u8

    if (button(&game.ui, inputState, rl.Rectangle {
      width = 150,
      height = 50,
    }, format_cost_and_scaling(game, .Shield, buf[:]), player.color) && player.energy >= auto_cast game.tileTypeStats[.Shield].scalingCost) {
      tile.durability += game.tileTypeStats[.Shield].scaling
      player.energy -= auto_cast game.tileTypeStats[.Shield].scalingCost
    }
    
    if (button(&game.ui, inputState, rl.Rectangle {
      width = 150,
      height = 50,
    }, "rotate", player.color)) {
      tile.direction = HexDirection((u8(tile.direction)+1)%6)
    }
    
    row_layout_end(&game.ui)
  }
}

EditMode :: enum {
  Placing,
  Clicking,
}

next_to :: proc(a: HalfGridPosition, b: HalfGridPosition) -> (bool, HexDirection) {
  for point, i in directions {
    if a + point == b {
      return true, HexDirection(i)
    }
  }
  return false, HexDirection(0)
}

test_adjacent_cell :: proc(game: ^Game, currentPlayerIndex: u8, p: HalfGridPosition, test: proc(game: ^Game, currentPlayerIndex: u8, tile: ^Tile) -> bool) -> bool {
  for point in directions {
    if test(game, currentPlayerIndex, get_tile(&game.tileGrid, point + p)) {
      return true;
    }
  }

  return false;
}

render_number :: proc(spos: la.Vector2f32, number: u8) {
  buf: [2]u8
  buf[0] = number + '0'
  buf[1] = 0

  str: cstring = transmute(cstring)&buf

  width := rl.MeasureText(str, 20)
  rl.DrawText(str, i32(spos.x) - width / 2, i32(spos.y) - 20 / 2, 20, rl.BLACK)
}

render_gameboard :: proc(game: ^Game, currentPlayerIndex: u8) {
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
    }

    visibility := tile.visibility[currentPlayerIndex]

    if ((currentPlayerIndex == tile.playerIndex || visibility == .Visible || visibility == .VeryVisible) && game.state == .Playing || game.state == .Winner) {
      spos := get_screen_position(&game.tileGrid, pos)

      switch tile.type {
      case .Cannon:
        rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{200, 200, 200, 255})
      case .Mortar:
        rl.DrawCircle(i32(spos.x)+15, i32(spos.y), 10, rl.Color{200, 200, 200, 255})
        rl.DrawCircle(i32(spos.x), i32(spos.y)+15, 10, rl.Color{200, 200, 200, 255})
        rl.DrawCircle(i32(spos.x)+7, i32(spos.y)+7, 10, rl.Color{200, 200, 200, 255})
        
        if currentPlayerIndex == tile.playerIndex || visibility == .VeryVisible || game.state == .Winner {
          render_number(spos, tile.damage)
        }
      case .Telescope:
        rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{255, 255, 0, 255})
        rl.DrawCircle(i32(spos.x), i32(spos.y), 18, rl.Color{255, 255, 255, 255})
      case .Shield:
        fill_hexagon(i32(spos.x), i32(spos.y), 20, rl.Color{200, 200, 200, 255})

        if currentPlayerIndex == tile.playerIndex || visibility == .VeryVisible {
          render_number(spos, tile.durability)

          dir := directionHexnormalized[tile.direction] * 7

          rl.DrawTriangle(
            spos + directionHexnormalized[(i8(tile.direction)+1)%6] * 8 + dir,
            spos + directionHexnormalized[(i8(tile.direction)-1 == -1) ? 5 : i8(tile.direction)-1] * 8 + dir, 
            spos + directionHexnormalized[tile.direction] * 8 + dir, 
          rl.Color{0, 0, 0, 255})
        }
      case .Blocked:
        fill_hexagon(i32(spos.x), i32(spos.y), game.tileGrid.hexagonSize, rl.Color{255, 255, 255, 255})
      case .Free:
      case .Nuke:
      case .Land:
      case .BlastTarget:
      case .MortarTarget:
      }
    }

    if game.state != .Playing {
      continue
    }

    for entityId in tile.entityIds {
      if entityId == 0 {
        continue
      }

      entity := game.entities[entityId-1]

      if entity.playerIndex == currentPlayerIndex {
        spos := get_screen_position(&game.tileGrid, pos)
        rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{255, 0, 0, 125})
        rl.DrawCircle(i32(spos.x), i32(spos.y), 10, rl.Color{255, 255, 255, 125})
        rl.DrawCircle(i32(spos.x), i32(spos.y), 5, rl.Color{255, 0, 0, 125})
      }
    }
  }
}

append_entityId :: proc(tile: ^Tile, entityId: u32) {
  for i in 0..<len(tile.entityIds) {
    id := &tile.entityIds[i]
    if id^ == 0 {
      id^ = entityId
      return
    }
  }
}

add_entity :: proc(game: ^Game, currentPlayerIndex: u8, halfgridPos: HalfGridPosition, entity: SimulationEntity, type: EntityType) {
  tile := get_tile(&game.tileGrid, halfgridPos)

  append_entityId(tile, game.entity_count+1)

  game.entities[game.entity_count] = entity

  entity := &game.entities[game.entity_count]

  entity.playerIndex = currentPlayerIndex
  entity.halfgridPos = halfgridPos
  entity.completed = false
  entity.type = type

  game.entity_count += 1
}

pay_active_tile_cost :: proc(game: ^Game, player: ^Player) -> bool {
  req_energy := game.tileTypeStats[player.selectedTileType].cost

  if u16(req_energy) > player.energy {
    return false
  }

  player.energy -= u16(req_energy)
  return true
}

within_game_bounds :: proc(game: ^Game, halfgridPos: HalfGridPosition) -> bool {
  return within_halfgrid_range(game.tileGrid.size, halfgridPos)
}

place_tile :: proc(game: ^Game, inputState: ^InputState, currentPlayerIndex: u8) {
  player := &game.players[currentPlayerIndex]
  halfgridPos := get_tile_grid_pos(&game.tileGrid, inputState.mousePos)
  tile := get_tile(&game.tileGrid, halfgridPos)
  activeTile, activeTileHalfgridPos := get_active_tile(&game.tileGrid, player)
  is_next, dir := next_to(halfgridPos, activeTileHalfgridPos)

  if inputState.leftButton != .Pressed {
    return
  }

  if !within_game_bounds(game, halfgridPos) {
    return
  }

  if player.selectedTileType == .Nuke && within_game_bounds(game, halfgridPos) && pay_active_tile_cost(game, player) {
    add_entity(game, currentPlayerIndex, halfgridPos, SimulationEntity {
      damage = game.tileTypeStats[.BlastTarget].cost
    }, EntityType.Nuke)
  }
  
  if player.selectedTileType == .MortarTarget && within_game_bounds(game, halfgridPos) && pay_active_tile_cost(game, player) {
    add_entity(game, currentPlayerIndex, halfgridPos, SimulationEntity {
      damage = activeTile.damage
    }, EntityType.MortarShot)

    player.activeTileId = 0
    player.editMode = .Clicking
  }
   
  if player.selectedTileType == .BlastTarget && is_next && pay_active_tile_cost(game, player) && within_game_bounds(game, halfgridPos) {
    pos := get_screen_position(&game.tileGrid, activeTileHalfgridPos)
    fwd_pos := get_screen_position(&game.tileGrid, activeTileHalfgridPos - directions[dir])
    vel := (fwd_pos - pos)

    add_entity(game, currentPlayerIndex, halfgridPos, SimulationEntity {
      shot = Shot {
        velocity = vel * CANNONBALL_SPEED,
        position = fwd_pos + (pos - fwd_pos) * 0.25
      },
      damage = game.tileTypeStats[.BlastTarget].damage
    }, EntityType.Shot)

    player.activeTileId = 0
    player.editMode = .Clicking

    return
  }

  if player.selectedTileType != .Land && (tile.type != .Land || tile.playerIndex != currentPlayerIndex) {
    return 
  }

  if player.selectedTileType == .Land && tile.type == .Land {
    return
  }

  next_to_own_territory :: proc(game: ^Game, currentPlayerIndex: u8, tile: ^Tile) -> bool {
    player := &game.players[currentPlayerIndex]
    return tile.playerIndex == currentPlayerIndex && tile.type != .Blocked && tile.type != .Free
  }

  if !test_adjacent_cell(game, currentPlayerIndex, halfgridPos, next_to_own_territory) && player.selectedTileType == .Land {
    return
  } 

  if pay_active_tile_cost(game, player) {
    tile.visibility[currentPlayerIndex] = .Invisible
    tile.playerIndex = currentPlayerIndex
    tile.type = player.selectedTileType
  
    if player.selectedTileType == .Shield {
      tile.durability = game.tileTypeStats[.Shield].durability
    }
    
    if player.selectedTileType == .Mortar {
      tile.damage = game.tileTypeStats[.Mortar].damage
    }

    if tile.type == .Telescope {
      for dir in directions {
        pos := halfgridPos

        for within_game_bounds(game, pos) {
          pos += dir

          get_tile(&game.tileGrid, pos).visibility[currentPlayerIndex] = .VeryVisible
        }
      }
    }
  }   
}

start_next_turn :: proc (game: ^Game, currentPlayerIndex: u8) {
  player := &game.players[currentPlayerIndex]
  player.playerState = .Done

  all_done: bool = true
  for i in 0..<game.playerCount {
    player := &game.players[i]

    if player.playerState != .Done {
      all_done = false
    }
  }

  fmt.println(all_done)

  if !all_done {
    return
  }
  
  for i in 0..<game.playerCount {
    player := &game.players[i]
    player.playerState = .Playing
    player.energy = game.stats.energyPerRound
    game.rounds += 1
    game.state = .Simulate
  }
}

ui_layout :: proc(game: ^Game, inputState: ^InputState, currentPlayerIndex: u8) {
  ui := &game.ui
  // ui buttonstrip
  row_layout(ui, .Right, {10, 10}, 10)
  
  player := &game.players[currentPlayerIndex]

  if (button(ui, inputState, rl.Rectangle {
    width = 100,
    height = 75,
  }, "cannon", player.color)) {
    player.selectedTileType = .Cannon
    player.editMode = .Placing
  }
  
  if (button(ui, inputState, rl.Rectangle {
    width = 100,
    height = 75,
  }, "land", player.color)) {
    player.selectedTileType = .Land
    player.editMode = .Placing
  }
  
  if (button(ui, inputState, rl.Rectangle {
    width = 100,
    height = 75,
  }, "shield", player.color)) {
    player.selectedTileType = .Shield
    player.editMode = .Placing
  }

  //if player.nukes != 0 {
    if (button(ui, inputState, rl.Rectangle {
      width = 100,
      height = 75,
    }, "nuke", player.color)) {
      player.selectedTileType = .Nuke
      player.editMode = .Placing
    }
  //}  

  if (button(ui, inputState, rl.Rectangle {
    width = 100,
    height = 75,
  }, "mortar", player.color)) {
    player.selectedTileType = .Mortar
    player.editMode = .Placing
  }
  
  if (button(ui, inputState, rl.Rectangle {
    width = 100,
    height = 75,
  }, "lookout", player.color)) {
    player.selectedTileType = .Telescope
    player.editMode = .Placing
  }

  if (button(ui, inputState, rl.Rectangle {
    width = 100,
    height = 75,
  }, "click", player.color)) {
    player.editMode = .Clicking
  }

  row_layout_end(ui)
  
  row_layout(ui, .Left, {f32(rl.GetScreenWidth()-10), f32(rl.GetScreenHeight()-10) - 75}, 10)
  
  if (button(ui, inputState, rl.Rectangle {
    width = 150,
    height = 75,
  }, "end turn", player.color)) {
    start_next_turn(game, currentPlayerIndex)
  }
 
  row_layout_end(ui)

  row_layout(ui, .Right, la.Vector2f32 { 10, player.inputState.screenSize.y - 30 }, 10)

  buf: [8]u8
  text_display(ui, { width = 20, height = 20 }, strconv.itoa(buf[:], int(game.rounds)), rl.BLACK)
  
  buf2: [8]u8
  str := strconv.itoa(buf2[:], int(player.energy))
  buf2[len(str)] = 'e'
  text_display(ui, { width = 20, height = 20 }, cast(string)buf2[:], rl.BLACK)
  
  text_display(ui, rl.Rectangle {
    width = 20,
    height = 20,
  }, player.username, player.color)

  row_layout_end(ui)
}

apply_friction :: proc(v: ^la.Vector2f32, f: f32) {
  if v.x > 0 {
    v.x -= f
  } else {
    v.x += f
  }

  if v.y > 0 {
    v.y += f
  } else {
    v.y += f
  }

  if abs(v.y) <= f {
    v.y = 0
  }
  
  if abs(v.x) <= f {
    v.x = 0
  }
}

complete_entity :: proc(game: ^Game, entity: ^SimulationEntity) {
  game.completed_entities += 1
  entity.completed = true

  origin_tile := get_tile(&game.tileGrid, entity.halfgridPos)
  // This wipes all on that tile but none should stay on it anyway
  origin_tile.entityIds = {}
}

damage_tile :: proc(tile: ^Tile, amount: u8) {
  if amount > tile.durability {
    tile^ = {}
  } else {
    tile.durability -= amount
  }

  for i in 0..<MAX_PLAYERS {
    if tile.visibility[i] == .Invisible {
      tile.visibility[i] = .Visible
    }
  }
}

crown_winner :: proc(game: ^Game) {
  playerExists: [MAX_PLAYERS]bool = {}

  for i in i16(-HALF_MAX_GRID_SIZE)..<i16(HALF_MAX_GRID_SIZE) {
    for j in i16(-HALF_MAX_GRID_SIZE)..<i16(HALF_MAX_GRID_SIZE) {
      if abs(i) % 2 != abs(j) % 2 {
        continue;
      }

      if within_halfgrid_range(game.tileGrid.size, {i, j}) {
        playerExists[get_tile(&game.tileGrid, {i, j}).playerIndex] = true
      }
    }
  }

  lastPlayerIdx: i8 = -1
  lastPlayerCount: u8 = 0

  for exists, i in playerExists {
    if exists {
      lastPlayerIdx = i8(i)
      lastPlayerCount += 1
    }
  }

  if lastPlayerCount == 1 {
    assert(lastPlayerIdx >= 0)
    game.winnerIdx = u8(lastPlayerIdx)
    game.state = .Winner
  }
}

simulate :: proc(game: ^Game, dt: f32) {
  friction :: 0.01 // tiles/second^2
  size :: 24

  if game.completed_entities == game.entity_count {
    game.entity_count = 0
    game.completed_entities = 0
    game.state = .Playing

    crown_winner(game)
    return
  }

  for i in 0..<game.entity_count {
    entity := &game.entities[i]
      
    if entity.completed {
      continue
    }

    switch entity.type { 
    case .MortarShot:
      tile := get_tile(&game.tileGrid, entity.halfgridPos)
      damage_tile(get_tile(&game.tileGrid, entity.halfgridPos), entity.damage)
      
      complete_entity(game, entity)
    case .Nuke:
      damage_tile(get_tile(&game.tileGrid, entity.halfgridPos), entity.damage)

      for dir in directions {
        damage_tile(get_tile(&game.tileGrid, entity.halfgridPos + dir), entity.damage)
      }

      complete_entity(game, entity)
    case .Shot: 
      shot := &entity.shot

      prevpos := shot.position

      shot.position += shot.velocity * dt
      shot.velocity += math.sign(shot.velocity.x/shot.velocity.y) * friction * dt

      apply_friction(&shot.velocity, friction * dt)

      halfgridPos := get_tile_grid_pos(&game.tileGrid, shot.position)
      tile := get_tile(&game.tileGrid, halfgridPos)

      screenHalfPos := get_screen_position(&game.tileGrid, halfgridPos)

      prev_tile := get_tile(&game.tileGrid, get_tile_grid_pos(&game.tileGrid, prevpos))

      if prev_tile != tile && prev_tile.playerIndex != entity.playerIndex {
        damage_tile(prev_tile, entity.damage)
      }
      
      if tile.type == .Shield {
        bounce_dir := directions[tile.direction]

        fwd_pos := get_screen_position(&game.tileGrid, halfgridPos + bounce_dir)
        vel := (fwd_pos - screenHalfPos)

        shot.velocity = vel * CANNONBALL_SPEED
      }

      if !within_halfgrid_range(game.tileGrid.size, halfgridPos) {
        complete_entity(game, entity)  
      }

      rl.DrawCircle(i32(shot.position.x), i32(shot.position.y), size, rl.BLACK)
    }
  }
}

update_game :: proc(game: ^Game, dt: f32, currentPlayerIndex: u8, virtual: bool) {
  player := &game.players[currentPlayerIndex]
   
  if game.state != .GameSelector {
    update_tilegrid_offset(&game.tileGrid, player.inputState)

    if !virtual {
      render_gameboard(game, currentPlayerIndex)
    }
  }

  switch game.state {
  case .GameSelector:
    if (button(&game.ui, player.inputState, rl.Rectangle{
      x = player.inputState.screenSize.x/2 - 150,
      y = player.inputState.screenSize.y/2 - 75,
      width = 150,
      height = 150,
    }, "mini", rl.GRAY)) {
      hexagonSize: i32 = 30

      game.tileGrid = TileGrid {
        size = 6,
        hexagonSize = hexagonSize,
      }
     
      get_tile(&game.tileGrid, {2, 2})^ = Tile {
        playerIndex = 0,
        type = .Land,
        visibility = {},
      }
      
      get_tile(&game.tileGrid, {-2, -2})^ = Tile {
        playerIndex = 1,
        type = .Land,
        visibility = {},
      }

      start_next_turn(game, 0)
    }
    
    if (button(&game.ui, player.inputState, rl.Rectangle{
      x = player.inputState.screenSize.x/2,
      y = player.inputState.screenSize.y/2 - 75,
      width = 150,
      height = 150,
    }, "big", rl.GRAY)) {
      hexagonSize: i32 = 30

      game.tileTypeStats[.Nuke] = {NA, NA, 2, 5, NA}

      game.tileGrid = TileGrid {
        size = 8,
        hexagonSize = hexagonSize,
      }
     
      get_tile(&game.tileGrid, {3, 3})^ = Tile {
        playerIndex = 0,
        type = .Land,
        visibility = {},
      }
      
      get_tile(&game.tileGrid, {-3, -3})^ = Tile {
        playerIndex = 1,
        type = .Land,
        visibility = {},
      }
      
      game.stats.energyPerRound = 5
      
      start_next_turn(game, 0)
    }
    
    rl.DrawCircle(i32(player.inputState.mousePos.x), i32(player.inputState.mousePos.y), 12, rl.BLACK)
  case .Winner:
    within_button := within_button(&game.ui, player.inputState, rl.Rectangle{
      x = player.inputState.screenSize.x/2 - 100,
      y = player.inputState.screenSize.y/2 - 0,
      width = 100,
      height = 40,
    }, "peek", player.color)

    if (!within_button || player.inputState.leftButton == .Up) {
      rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{
        0, 0, 0, 150
      })

      if game.winnerIdx == currentPlayerIndex {
        text_display(&game.ui, rl.Rectangle{
          x = player.inputState.screenSize.x/2 - 75,
          y = player.inputState.screenSize.y/2 - 120,
          width = 150,
          height = 150,
        }, "Victory", rl.WHITE, 50)
      }

      if (button(&game.ui, player.inputState, rl.Rectangle{
        x = player.inputState.screenSize.x/2 - 0,
        y = player.inputState.screenSize.y/2 - 0,
        width = 100,
        height = 40,
      }, "continue", player.color)) {
        game.state = .GameSelector
      }
    }
  case .Paused:
    play := button(&game.ui, player.inputState, rl.Rectangle{
      x = player.inputState.screenSize.x/2 - 75,
      y = player.inputState.screenSize.y/2 - 75,
      width = 150,
      height = 150,
    }, "play", rl.GRAY)

    if play {
      game.state = .Playing
    }
  case .Simulate:
    simulate(game, dt)
  case .Playing:
    if player.playerState == .Done {
      return
    }

    switch player.editMode {
      case .Placing:
        place_tile(game, player.inputState, currentPlayerIndex)
      case .Clicking:
        click_tile(game, player.inputState, currentPlayerIndex)
    }        

    ui_layout(game, player.inputState, currentPlayerIndex)

    hover_tilegrid(&game.tileGrid, player.inputState, player, &game.ui, virtual)
  }    
}

AppState :: enum {
  Connecting,
  Playing,
}

App :: struct {
  network: Network,
  gameInstance: Game,
  playerNames: [MAX_PLAYERS]string,
  state: AppState,
  playerCount: u8,
  playerIndex: u8,
}

MouseState :: enum {
  Up,
  Down,
  Pressed,
}

InputState :: struct {
  mousePos: la.Vector2f32,
  screenSize: la.Vector2f32,
  leftButton: MouseState,
}

init_app :: proc(app: ^App) {
  init_network(&app.network)
}

get_button_state :: proc() -> MouseState {
  if rl.IsMouseButtonPressed(.LEFT) {
    return .Pressed
  }

  if rl.IsMouseButtonDown(.LEFT) {
    return .Down
  }
   
  if rl.IsMouseButtonUp(.LEFT) {
    return .Up
  }

  unreachable()
}

get_input_state :: proc() -> InputState {
  return InputState {
    mousePos = rl.GetMousePosition(),
    leftButton = get_button_state(),
    screenSize = la.Vector2f32{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}, 
  }
}

init_game :: proc(app: ^App, myInputState: ^InputState) {
  app.playerCount = app.network.lobby.client_count
  app.playerIndex = get_client_player_idx(&app.network)
  
  app.gameInstance.playerCount = app.playerCount
  
  for i in 0..<app.playerCount {
    client := &app.network.lobby.clients[i]
    app.playerNames[i] = string(client.name_buf[:client.name_len])
    app.gameInstance.players[i].inputState = &app.network.lobby.inputStates[i]
  }  
 
  for playerName, i in app.playerNames {
    player := &app.gameInstance.players[i]

    player.color = playerColors[i]
    player.username = app.playerNames[i]
    player.selectedTileType = .Land
  }
  
  app.gameInstance.tileTypeStats = defaultTileTypeStats
  app.gameInstance.stats = defaultGameStats

  //init_tilegrid(&app.gameInstance.tileGrid, &app.gameInstance.ui)    
}

update_app :: proc(app: ^App, dt: f32) {
  myInputState := get_input_state()
  update_network(&app.network, &myInputState)

  switch app.state {
  case .Playing:
    for i in 0..<app.playerCount {
      virtual := i != app.playerIndex

      if !virtual {
        update_tilegrid_offset(&app.gameInstance.tileGrid, &myInputState)
        app.network.lobby.inputStates[i] = myInputState
      }
      
      app.gameInstance.ui.virtual = virtual
  
      update_game(&app.gameInstance, dt, u8(i), virtual)
    } 
  case .Connecting:  
    if app.network.state == .Connected {
      app.state = .Playing
      init_game(app, &myInputState)
    }
  }
  
  reset_input_state(&app.network)
}

main :: proc() {
  rl.InitWindow(800, 800, "hexabomb")
  rl.SetWindowState({.WINDOW_RESIZABLE})

  app: App
  init_app(&app)

  for !rl.WindowShouldClose() {
    rl.BeginDrawing()
    rl.ClearBackground(rl.WHITE)

    update_app(&app, rl.GetFrameTime())

    rl.EndDrawing()
  }
}
