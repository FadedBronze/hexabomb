package main
import "core:math"
import rl "vendor:raylib"
import la "core:math/linalg"

MAX_GRID_SIZE :: 32 
HALF_MAX_GRID_SIZE :: MAX_GRID_SIZE / 2

HexDirection :: enum {
  Up,
  RightUp,
  RightDown,
  Down,
  LeftDown,
  LeftUp,
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

TileGrid :: struct {
  tiles: [MAX_GRID_SIZE * MAX_GRID_SIZE]Tile,
  hexagonSize: i32,
  offset: [2]i32,
  size: i16,
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

get_tile_grid_pos :: proc(tileGrid: ^TileGrid, position: la.Vector2f32) -> HalfGridPosition {
  grid_pos := get_halfgrid_pos(position - la.Vector2f32{f32(tileGrid.offset.x), f32(tileGrid.offset.y)}, tileGrid.hexagonSize)
  return { i16(grid_pos.x), i16(grid_pos.y) }
}

get_tile_grid_pos_safe :: proc(tileGrid: ^TileGrid, position: la.Vector2f32) -> (bool, HalfGridPosition) {
  pos := get_tile_grid_pos(tileGrid, position)
  return within_halfgrid_range(tileGrid.size, pos), pos
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

get_tile :: proc(tileGrid: ^TileGrid, pos: HalfGridPosition) -> ^Tile {
  idx := (pos.y + HALF_MAX_GRID_SIZE) * MAX_GRID_SIZE + (pos.x + HALF_MAX_GRID_SIZE)
  return &tileGrid.tiles[idx]
}

update_tilegrid_offset :: proc(tileGrid: ^TileGrid, inputState: ^InputState) {
  half_length := i32(f32(tileGrid.hexagonSize) * math.sqrt_f32(3) / 3)
  tileGrid.offset = {i32(inputState.screenSize.x) / 2 - half_length, i32(inputState.screenSize.y) / 2 - tileGrid.hexagonSize}
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

  halfgrid :=  get_tile_grid_pos(tileGrid, inputState.mousePos)

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
    case .Defense:
      fill_hexagon(i32(spos.x), i32(spos.y), 20, rl.Color{200, 200, 200, 255})
    }
  } else {
    outline_hexagon_halfgrid(halfgrid, tileGrid.offset, rl.RED, tileGrid.hexagonSize)
  }
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

render_gameboard :: proc(game: ^Game, currentPlayerIndex: u8) {
  tileGrid := &game.tileGrid

  for tile, i in tileGrid.tiles {
    i := i16(i)
    pos: HalfGridPosition = {(i % MAX_GRID_SIZE) - HALF_MAX_GRID_SIZE, (i / MAX_GRID_SIZE) - HALF_MAX_GRID_SIZE}

    if abs(pos.x) % 2 != abs(pos.y) % 2 {
      continue;
    }

    player := &game.players[tile.playerIndex]

    if tile.type != .Free && tile.type != .Blocked && tile.type != .BlastTarget {
      fill_hexagon_halfgrid(pos, tileGrid.offset, player.color, tileGrid.hexagonSize)
    }

    visibility := tile.visibility[currentPlayerIndex]

    if tile.type == .Blocked {
      fill_hexagon_halfgrid(pos, tileGrid.offset, rl.Color{255, 255, 255, 255}, game.tileGrid.hexagonSize)
    }

    if tile.type == .Free {
      fill_hexagon_halfgrid(pos, tileGrid.offset, rl.Color{0, 20, 128, 255}, tileGrid.hexagonSize)
    }

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
          dir := directionHexnormalized[tile.direction] * 7

          rl.DrawTriangle(
            spos + directionHexnormalized[(i8(tile.direction)+1)%6] * 8 + dir,
            spos + directionHexnormalized[(i8(tile.direction)-1 == -1) ? 5 : i8(tile.direction)-1] * 8 + dir, 
            spos + directionHexnormalized[tile.direction] * 8 + dir, 
          rl.Color{0, 0, 0, 255})
        }
      case .Defense:
        fill_hexagon(i32(spos.x), i32(spos.y), 20, rl.Color{200, 200, 200, 255})
        
        if currentPlayerIndex == tile.playerIndex || visibility == .VeryVisible {
          render_number(spos, tile.durability)
        }
      case .Blocked:
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

within_game_bounds :: proc(game: ^Game, halfgridPos: HalfGridPosition) -> bool {
  return within_halfgrid_range(game.tileGrid.size, halfgridPos)
}
