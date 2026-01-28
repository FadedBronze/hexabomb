package main

import "core:fmt"
import rl "vendor:raylib"
import "core:math"
import la "core:math/linalg"

MAX_GRID_SIZE :: 32 
CANNONBALL_SPEED :: 4
HALF_MAX_GRID_SIZE :: MAX_GRID_SIZE / 2
MAX_PLAYERS :: 4

tileTypeCost := []u16{
  0, 
  0,
  1,
  1,
  0,
  1,
  5,
  1,
  1,
  1,
}

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

Visibility :: enum {
  Visible,
  VeryVisible,
  Invisible,
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
  BetweenRounds,
  Playing,
  Simulate,
  PostSimulate,
  Paused,
}

Player :: struct {
  nukes: u8,
  color: rl.Color,
  selectedTileType: TileType,
  editMode: EditMode,
  energy: u16,
  username: string,
  activeTileId: u32,
  inputState: ^InputState,
  virtual: bool,
}

Game :: struct {
  ui: UI,

  state: GameState,
  order: bool,
  rounds: u32,

  playerCount: u8,
  players: [MAX_PLAYERS]Player,

  tileGrid: TileGrid,
  entities: [MAX_ENTITIES]SimulationEntity,
  entity_count: u32,
  completed_entities: u32,
}

get_tile :: proc(tileGrid: ^TileGrid, pos: HalfGridPosition) -> ^Tile {
  idx := (pos.y + HALF_MAX_GRID_SIZE) * MAX_GRID_SIZE + (pos.x + HALF_MAX_GRID_SIZE)
  return &tileGrid.tiles[idx]
}

init_tilegrid :: proc(tileGrid: ^TileGrid, ui: ^UI) {
  hexagonSize: i32 = 30

  tileGrid^ = TileGrid {
    size = 6,
    hexagonSize = hexagonSize,
  }

  update_tilegrid_offset(tileGrid)
  
  get_tile(tileGrid, {2, 2})^ = Tile {
    playerIndex = 0,
    type = .Land,
    visibility = .Invisible,
  }
  
  get_tile(tileGrid, {-2, -2})^ = Tile {
    playerIndex = 1,
    type = .Land,
    visibility = .Invisible,
  }
}

update_tilegrid_offset :: proc(tileGrid: ^TileGrid) {
  half_length := i32(f32(tileGrid.hexagonSize) * math.sqrt_f32(3) / 3)
  tileGrid.offset = {rl.GetScreenWidth() / 2 - half_length, rl.GetScreenHeight() / 2 - tileGrid.hexagonSize}
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

hover_tilegrid :: proc(tileGrid: ^TileGrid, player: ^Player, ui: ^UI, id := #caller_location) {
  if ui.activeId == empty_id() {
    ui.activeId = id
  }
  if ui.activeId != id {
    return
  }

  halfgrid := get_tile_grid_pos(tileGrid, rl.GetMousePosition())

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

click_tile :: proc(game: ^Game, currentPlayerIndex: u8) {
  halfgrid := get_tile_grid_pos(&game.tileGrid, rl.GetMousePosition())
  hovered_tile := get_tile(&game.tileGrid, halfgrid)

  player := &game.players[currentPlayerIndex]

  if rl.IsMouseButtonPressed(.LEFT) {
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
    row_layout(&game.ui, .Down, la.Vector2f32{f32(rl.GetScreenWidth()) - 10 - 75, f32(rl.GetScreenHeight()) / 2 - 52.5}, 5)

    if (button(&game.ui, rl.Rectangle {
      width = 75,
      height = 50,
    }, "+1", player.color) && player.energy >= 2) {
      tile.damage += 1
      player.energy -= 2
    }
    
    if (button(&game.ui, rl.Rectangle {
      width = 75,
      height = 50,
    }, "fire", player.color)) {
      player.editMode = .Placing
      player.selectedTileType = .MortarTarget
    }
    
    row_layout_end(&game.ui)
  }

  if tile != nil && tile.type == .Shield {
    row_layout(&game.ui, .Down, la.Vector2f32{f32(rl.GetScreenWidth()) - 10 - 75, f32(rl.GetScreenHeight()) / 2 - 52.5}, 5)

    if (button(&game.ui, rl.Rectangle {
      width = 75,
      height = 50,
    }, "+1", player.color) && player.energy >= 1) {
      tile.durability += 1
      player.energy -= 1
    }
    
    if (button(&game.ui, rl.Rectangle {
      width = 75,
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

    if ((currentPlayerIndex == tile.playerIndex || tile.visibility == .Visible || tile.visibility == .VeryVisible) && game.state == .Playing) {
      spos := get_screen_position(&game.tileGrid, pos)

      switch tile.type {
      case .Cannon:
        rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{200, 200, 200, 255})
      case .Mortar:
        rl.DrawCircle(i32(spos.x)+15, i32(spos.y), 10, rl.Color{200, 200, 200, 255})
        rl.DrawCircle(i32(spos.x), i32(spos.y)+15, 10, rl.Color{200, 200, 200, 255})
        rl.DrawCircle(i32(spos.x)+7, i32(spos.y)+7, 10, rl.Color{200, 200, 200, 255})
        
        if currentPlayerIndex == tile.playerIndex || tile.visibility == .VeryVisible {
          render_number(spos, tile.damage)
        }
      case .Telescope:
        rl.DrawCircle(i32(spos.x), i32(spos.y), 20, rl.Color{255, 255, 0, 255})
        rl.DrawCircle(i32(spos.x), i32(spos.y), 18, rl.Color{255, 255, 255, 255})
      case .Shield:
        fill_hexagon(i32(spos.x), i32(spos.y), 20, rl.Color{200, 200, 200, 255})

        if currentPlayerIndex == tile.playerIndex || tile.visibility == .VeryVisible {
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

pay_active_tile_cost :: proc(player: ^Player) -> bool {
  req_energy := tileTypeCost[player.selectedTileType]

  if req_energy > player.energy {
    return false
  }

  player.energy -= req_energy
  return true
}

within_game_bounds :: proc(game: ^Game, halfgridPos: HalfGridPosition) -> bool {
  return within_halfgrid_range(game.tileGrid.size, halfgridPos)
}

place_tile :: proc(game: ^Game, currentPlayerIndex: u8) {
  player := &game.players[currentPlayerIndex]
  halfgridPos := get_tile_grid_pos(&game.tileGrid, rl.GetMousePosition())
  tile := get_tile(&game.tileGrid, halfgridPos)
  activeTile, activeTileHalfgridPos := get_active_tile(&game.tileGrid, player)
  is_next, dir := next_to(halfgridPos, activeTileHalfgridPos)

  if !rl.IsMouseButtonPressed(.LEFT) {
    return
  }

  if !within_game_bounds(game, halfgridPos) {
    return
  }

  if player.selectedTileType == .Nuke && within_game_bounds(game, halfgridPos) && pay_active_tile_cost(player) && player.nukes > 0 {
    player.nukes -= 1
    add_entity(game, currentPlayerIndex, halfgridPos, SimulationEntity {
      damage = 2
    }, EntityType.Nuke)
  }
  
  if player.selectedTileType == .MortarTarget && within_game_bounds(game, halfgridPos) && pay_active_tile_cost(player) {
    add_entity(game, currentPlayerIndex, halfgridPos, SimulationEntity {
      damage = activeTile.damage
    }, EntityType.MortarShot)

    player.activeTileId = 0
    player.editMode = .Clicking
  }
   
  if player.selectedTileType == .BlastTarget && is_next && pay_active_tile_cost(player) && within_game_bounds(game, halfgridPos) {
    pos := get_screen_position(&game.tileGrid, activeTileHalfgridPos)
    fwd_pos := get_screen_position(&game.tileGrid, activeTileHalfgridPos - directions[dir])
    vel := (fwd_pos - pos)

    add_entity(game, currentPlayerIndex, halfgridPos, SimulationEntity {
      shot = Shot {
        velocity = vel * CANNONBALL_SPEED,
        position = fwd_pos + (pos - fwd_pos) * 0.25
      },
      damage = 1
    }, EntityType.Shot)

    player.activeTileId = 0
    player.editMode = .Clicking

    return
  }

  if player.selectedTileType != .Land && (tile.type != .Land || tile.playerIndex != currentPlayerIndex) {
    return 
  }

  next_to_own_territory :: proc(game: ^Game, currentPlayerIndex: u8, tile: ^Tile) -> bool {
    player := &game.players[currentPlayerIndex]
    return tile.playerIndex == currentPlayerIndex && tile.type != .Blocked && tile.type != .Free
  }

  if !test_adjacent_cell(game, currentPlayerIndex, halfgridPos, next_to_own_territory) && player.selectedTileType == .Land {
    return
  } 

  if pay_active_tile_cost(player) {
    tile.visibility = .Invisible
    tile.playerIndex = currentPlayerIndex
    tile.type = player.selectedTileType

    if player.selectedTileType == .Shield {
      tile.durability = 1
    }
    
    if player.selectedTileType == .Mortar {
      tile.damage = 1
    }

    if tile.type == .Telescope {
      for dir in directions {
        pos := halfgridPos

        for within_game_bounds(game, pos) {
          pos += dir

          get_tile(&game.tileGrid, pos).visibility = .VeryVisible
        }
      }
    }
  }   
}

start_next_turn :: proc (game: ^Game, currentPlayerIndex: u32) {
  //BIG TODO

  //if game.order {
  //  currentPlayerIndex += 1

  //  if currentPlayerIndex == game.playerCount {
  //    currentPlayerIndex = game.playerCount - 1
  //    game.state = .BetweenRounds
  //    game.order = !game.order
  //
  //    game.rounds += 1
  //  }
  //} else {
  //  if currentPlayerIndex == 0 {
  //    currentPlayerIndex = 1
  //    game.state = .BetweenRounds
  //    game.order = !game.order
  //    
  //    game.rounds += 1
  //  }

  //  currentPlayerIndex -= 1  
  //}

  //game.tileGrid.activeTileId = 0
  //player := &game.players[currentPlayerIndex]
  //player.energy = 3
}

ui_layout :: proc(game: ^Game, currentPlayerIndex: u8) {
  ui := &game.ui
  // ui buttonstrip
  row_layout(ui, .Right, {10, 10}, 10)
  
  player := &game.players[currentPlayerIndex]

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

  if player.nukes != 0 {
    if (button(ui, rl.Rectangle {
      width = 100,
      height = 75,
    }, "nuke", player.color)) {
      player.selectedTileType = .Nuke
      player.editMode = .Placing
    }
  }  

  if (button(ui, rl.Rectangle {
    width = 100,
    height = 75,
  }, "mortar", player.color)) {
    player.selectedTileType = .Mortar
    player.editMode = .Placing
  }
  
  if (button(ui, rl.Rectangle {
    width = 100,
    height = 75,
  }, "lookout", player.color)) {
    player.selectedTileType = .Telescope
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
    //BIG TODO
    //start_next_turn(game)
  }
 
  text_display(ui, rl.Rectangle {
    width = 100,
    height = 75,
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

  tile.visibility = .Visible
}

simulate :: proc(game: ^Game, dt: f32) {
  friction :: 0.01 // tiles/second^2
  size :: 24

  if game.completed_entities == game.entity_count {
    game.entity_count = 0
    game.completed_entities = 0
    game.state = .PostSimulate
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
      //  availableDirs: [6][2]i16
      //  availableDirCount: u32 = 0

      //  for dir in directions {
      //    tile := get_tile(&game.tileGrid, halfgridPos + dir)
      //    if tile.type == .Free && within_halfgrid_range(game.tileGrid.size, halfgridPos + dir) {
      //      availableDirs[availableDirCount] = dir
      //      availableDirCount += 1
      //    }
      //  }

        
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

update_game :: proc(game: ^Game, dt: f32, currentPlayerIndex: u8) {
    player := &game.players[currentPlayerIndex]
 
    update_tilegrid_offset(&game.tileGrid)
    render_gameboard(game, currentPlayerIndex)

    switch game.state {
      case .Paused:
        play := button(&game.ui, rl.Rectangle{
          x = f32(rl.GetScreenWidth())/2 - 75,
          y = f32(rl.GetScreenHeight())/2 - 75,
          width = 150,
          height = 150,
        }, "play", rl.GRAY)

        if rl.IsKeyPressed(.P) || play {
          game.state = .Playing
        }
      case .PostSimulate:
        start := button(&game.ui, rl.Rectangle{
          x = f32(rl.GetScreenWidth())/2 - 75,
          y = f32(rl.GetScreenHeight())/2 - 75,
          width = 150,
          height = 150,
        }, "continue", rl.GRAY)

        if start {
          game.state = .Playing
        }
      case .BetweenRounds:
        start := button(&game.ui, rl.Rectangle{
          x = f32(rl.GetScreenWidth())/2 - 75,
          y = f32(rl.GetScreenHeight())/2 - 75,
          width = 150,
          height = 150,
        }, "start", rl.GRAY)

        if start {
          game.state = .Simulate
        }
      case .Simulate:
        simulate(game, dt)
      case .Playing:
        if rl.IsKeyPressed(.P) {
          game.state = .Paused
        }

        switch player.editMode {
          case .Placing:
            place_tile(game, currentPlayerIndex)
          case .Clicking:
            click_tile(game, currentPlayerIndex)
        }    

        ui_layout(game, currentPlayerIndex)
        hover_tilegrid(&game.tileGrid, player, &game.ui)
    }    
}

AppState :: enum {
  Connecting,
  Playing,
}

App :: struct {
  network: Network,
  gameInstance: Game,
  inputStates: [MAX_PLAYERS]InputState,
  playerNames: [MAX_PLAYERS]string,
  state: AppState,
  playerCount: u8,
  playerIndex: u8,
}

MouseState :: enum {
  Down,
  Pressed,
  Up,
  None,
}

InputState :: struct {
  mousePos: la.Vector2f32,
  screenSize: la.Vector2f32,
  leftButton: MouseState,
}

init_app :: proc(app: ^App) {
  init_network(&app.network)
}

init_game :: proc(app: ^App, playerNames: []string) {
  for i in 0..<app.network.lobby.client_count {
    client := &app.network.lobby.clients[i]
    app.playerNames[i] = string(client.name_buf[:client.name_len])
  }

  app.playerCount = app.network.lobby.client_count
  app.playerIndex = get_client_player_idx(&app.network)

  app.gameInstance = Game {
    playerCount = u8(len(playerNames)),
  }

  for playerName, i in playerNames {
    app.gameInstance.players[i] = Player {
      color = playerColors[i],
      username = playerNames[i],
      nukes = 1,
      selectedTileType = .Land,
    }
  }

  init_tilegrid(&app.gameInstance.tileGrid, &app.gameInstance.ui)
}

get_button_state :: proc() -> MouseState {
  if rl.IsMouseButtonDown(.LEFT) {
    return .Down
  }
  
  if rl.IsMouseButtonPressed(.LEFT) {
    return .Pressed
  }
  
  if rl.IsMouseButtonUp(.LEFT) {
    return .Up
  }

  return .None
}

update_app :: proc(app: ^App, dt: f32) {
  switch app.state {
  case .Playing:
    for i in 0..<app.playerCount {
      if i == app.playerIndex {
        app.inputStates[i] = InputState {
          mousePos = rl.GetMousePosition(),
          leftButton = get_button_state(),
          screenSize = la.Vector2f32{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}, 
        }
      } else {
      }
      
      update_game(&app.gameInstance, dt, u8(i))
    }
  case .Connecting:
    update_network(&app.network)
    
    if app.network.state == .Connected {
      app.state = .Playing
      init_game(app, app.playerNames[:app.playerCount])
    }
  }
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
