package main
import "core:strconv"
import "core:fmt"
import rl "vendor:raylib"
import "core:math"
import la "core:math/linalg"
import "core:math/rand"

CANNONBALL_SPEED :: 4
MAX_PLAYERS :: 4

TileType :: enum {
  Blocked,
  Free,
  Land,
  Cannon,
  Shield,
  BlastTarget,
  Nuke,
  Mortar,
  MortarTarget,
  Telescope,
  Defense,
}

Visibility :: [MAX_PLAYERS]enum {
  Invisible,
  Visible,
  VeryVisible,
}

Cannon :: struct {
  direction: HexDirection,
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
  GotoLobby,
}

Player :: struct {
  tileLimits: [TileType]u8,
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
  limit: u8,
}

//NOT APPLICABLE
NA := max(u8)

defaultTileTypeStats := [TileType]TileTypeStat{
  .Free         = {NA, NA, NA, NA, 0,  NA}, 
  .Blocked      = {NA, NA, NA, NA, NA, NA},
  .Land         = {NA, NA, NA, 1,  0,  NA},
  .Cannon       = {NA, NA, NA, 1,  0,  NA},
  .Shield       = {NA, NA, NA, 0,  0,  NA},
  .BlastTarget  = {NA, NA, NA, 1,  0,  NA},
  .Nuke         = {NA, NA, 1,  3,  0,  NA},
  .Mortar       = {1,  2,  1,  1,  0,  NA},
  .MortarTarget = {NA, NA, NA, 1,  0,  NA},
  .Telescope    = {NA, NA, NA, 1,  0,  NA},
  .Defense      = {2,  1,  NA, 2,  3,  NA},
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

  seed: u64,
}

playerColors := [4]rl.Color {
  rl.BLUE,
  rl.RED,
  rl.GREEN,
  rl.ORANGE,
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
  within_bounds, halfgrid := get_tile_grid_pos_safe(&game.tileGrid, inputState.mousePos)

  if !within_bounds {
    return
  }

  hovered_tile := get_tile(&game.tileGrid, halfgrid)

  player := &game.players[currentPlayerIndex]

  if inputState.leftButton == .Pressed {
    if hovered_tile.type == .Cannon && hovered_tile.playerIndex == currentPlayerIndex {
      player.activeTileId = get_tile_id(halfgrid)
      
      player.editMode = .Placing
      player.selectedTileType = .BlastTarget
    }
    
    if (hovered_tile.type == .Mortar || hovered_tile.type == .Shield || hovered_tile.type == .Defense) && hovered_tile.playerIndex == currentPlayerIndex {
      player.activeTileId = get_tile_id(halfgrid)
    }
  }
}

render_active_tile :: proc(game: ^Game, inputState: ^InputState, currentPlayerIndex: u8) {
  player := &game.players[currentPlayerIndex]

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
  
  if tile != nil && tile.type == .Defense {
    row_layout(&game.ui, .Down, la.Vector2f32{f32(rl.GetScreenWidth()) - 10 - 150, f32(rl.GetScreenHeight()) / 2 - 52.5}, 5)

    buf: [32]u8

    if (button(&game.ui, inputState, rl.Rectangle {
      width = 150,
      height = 50,
    }, format_cost_and_scaling(game, .Defense, buf[:]), player.color) && player.energy >= auto_cast game.tileTypeStats[.Defense].scalingCost) {
      tile.durability += game.tileTypeStats[.Defense].scaling
      player.energy -= auto_cast game.tileTypeStats[.Defense].scalingCost
    }
    
    row_layout_end(&game.ui)
  }

  if tile != nil && tile.type == .Shield {
    row_layout(&game.ui, .Down, la.Vector2f32{f32(rl.GetScreenWidth()) - 10 - 150, f32(rl.GetScreenHeight()) / 2 - 52.5}, 5)

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

render_number :: proc(spos: la.Vector2f32, number: u8) {
  buf: [2]u8
  buf[0] = number + '0'
  buf[1] = 0

  str: cstring = transmute(cstring)&buf

  width := rl.MeasureText(str, 20)
  rl.DrawText(str, i32(spos.x) - width / 2, i32(spos.y) - 20 / 2, 20, rl.BLACK)
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

  if player.tileLimits[player.selectedTileType] == 0 {
    return false
  }

  if u16(req_energy) > player.energy {
    return false
  }

  player.energy -= u16(req_energy)

  if player.tileLimits[player.selectedTileType] != NA {
    player.tileLimits[player.selectedTileType] -= 1
  }

  return true
}

place_tile :: proc(game: ^Game, inputState: ^InputState, currentPlayerIndex: u8) {
  player := &game.players[currentPlayerIndex]
  within_bounds, halfgridPos := get_tile_grid_pos_safe(&game.tileGrid, inputState.mousePos)

  if !within_bounds {
    return
  }

  tile := get_tile(&game.tileGrid, halfgridPos)
  activeTile, activeTileHalfgridPos := get_active_tile(&game.tileGrid, player)
  is_next, dir := next_to(halfgridPos, activeTileHalfgridPos)

  if tile.type == .Blocked {
    return
  }

  if inputState.leftButton != .Pressed {
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
  
    tile.durability = game.tileTypeStats[tile.type].durability
    
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

force_start_next_turn :: proc (game: ^Game) {
  for i in 0..<game.playerCount {
    player := &game.players[i]
    player.playerState = .Playing
    player.energy = game.stats.energyPerRound
    game.rounds += 1
    game.state = .Simulate
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

  force_start_next_turn(game)
}

assign_tile_limits :: proc(game: ^Game) {
  for j in 0..<game.playerCount {
    player := &game.players[j]
    for tileStat, i in game.tileTypeStats {
      player.tileLimits[i] = tileStat.limit
    }
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
  }, "defense", player.color)) {
    player.selectedTileType = .Defense
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
  
  if (button(ui, inputState, rl.Rectangle {
    width = 150,
    height = 75,
  }, "lobby", player.color)) {
    player.playerState = .GotoLobby
    agreeingPlayers := 0

    for player in game.players[0:game.playerCount] {
      if player.playerState == .GotoLobby {
        agreeingPlayers += 1
      }
    }

    if f32(agreeingPlayers) / f32(game.playerCount) > 0.6 {
      game.state = .GameSelector
    }
  }
 
  row_layout_end(ui)

  row_layout(ui, .Right, la.Vector2f32 { 10, player.inputState.screenSize.y - 30 }, 10)

  {
    buf: [8]u8
    text_display(ui, { width = 20, height = 20 }, strconv.itoa(buf[:], int(game.rounds)), rl.BLACK)
  }
  
  {
    buf: [8]u8
    str := strconv.itoa(buf[:], int(player.energy))
    buf[len(str)] = 'e'
    text_display(ui, { width = 40, height = 20 }, cast(string)buf[:], rl.BLACK)
  }

  cost := game.tileTypeStats[player.selectedTileType].cost
  if cost != NA {
    buf: [8]u8
    buf[0] = '-'
    str := strconv.itoa(buf[1:], int(cost))
    buf[len(str)+1] = 'e'
    text_display(ui, { width = 40, height = 20 }, cast(string)buf[:], rl.RED)
  }
  
  {
    buf: [32]u8
    str: string
    if player.tileLimits[player.selectedTileType] != NA {
      str = strconv.itoa(buf[:], int(player.tileLimits[player.selectedTileType]))
    } else {
      str = "--"
      copy(buf[:], str)
    }
    copy(buf[len(str):], "")

    text_display(ui, { width = 40, height = 20 }, cast(string)buf[:len(str)+5], rl.BLACK)
  }
  
  text_display(ui, rl.Rectangle { width = 20, height = 20 }, player.username, player.color)
  
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

damage_tile :: proc(game: ^Game, halfGridPos: HalfGridPosition, amount: u8) {
  tile := get_tile(&game.tileGrid, halfGridPos)

  if game.tileTypeStats[tile.type].durability == NA {
    return
  }

  for direction in directions {
    nexttotile := get_tile(&game.tileGrid, halfGridPos + direction)

    if nexttotile.type == .Defense {
      tile = nexttotile
      break
    }
  }

  if amount > tile.durability {
    tile^ = {}
    tile.type = .Free
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

  fieldIterator: FieldIterator

  for {
    tile := iterate_field(&fieldIterator, &game.tileGrid)

    if tile == nil {
      break
    }
    
    playerExists[tile.playerIndex] = true
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
      damage_tile(game, entity.halfgridPos, entity.damage)
      
      complete_entity(game, entity)
    case .Nuke:
      damage_tile(game, entity.halfgridPos, entity.damage)

      for dir in directions {
        damage_tile(game, entity.halfgridPos + dir, entity.damage)
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

      prevgridpos := get_tile_grid_pos(&game.tileGrid, prevpos)

      prev_tile := get_tile(&game.tileGrid, prevgridpos)

      if prev_tile != tile && prev_tile.playerIndex != entity.playerIndex {
        damage_tile(game, prevgridpos, entity.damage)
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

FieldIterator :: struct {
  i: i16,
  j: i16,
}

iterate_field :: proc(iter: ^FieldIterator, tileGrid: ^TileGrid) -> ^Tile {
  for {
    iter.j += 1
    if iter.j >= MAX_GRID_SIZE {
      iter.i += 1
      iter.j = 0
    }
    
    if iter.i >= MAX_GRID_SIZE {
      return nil
    }

    x := iter.j - HALF_MAX_GRID_SIZE
    y := iter.i - HALF_MAX_GRID_SIZE

    if abs(x) % 2 != abs(y) % 2 {
      continue;
    }

    if within_halfgrid_range(tileGrid.size, {x, y}) {
      return get_tile(tileGrid, {x, y})
    }
  }  
}

randomize_field :: proc(tileGrid: ^TileGrid) {
  fieldIterator: FieldIterator
  for {
    if tile := iterate_field(&fieldIterator, tileGrid); tile != nil {
      randomSelection: [2]struct{
        tile: TileType,
        chanceRatio: u8,
      } = {
        {tile = .Free, chanceRatio = 2},
        {tile = .Blocked, chanceRatio = 1},
      }

      totalRatio: u8 = 0

      for selection in randomSelection {
        totalRatio += selection.chanceRatio
      }

      roll := u8(rand.float32() * f32(totalRatio))

      i := u8(0)
      for selection in randomSelection {
        if roll >= i && roll < i + selection.chanceRatio {
          tile.type = selection.tile
          break;
        } 
        
        i += selection.chanceRatio
      }
    } else {
      return
    }
  }
}

free_field :: proc(tileGrid: ^TileGrid) {
  fieldIterator: FieldIterator
  for {
    if tile := iterate_field(&fieldIterator, tileGrid); tile != nil {
      tile.type = .Free
    } else {
      return
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
    //TODO
    hexagonSize: i32 = 30

    if (button(&game.ui, player.inputState, rl.Rectangle{
      x = player.inputState.screenSize.x/2 - 75,
      y = player.inputState.screenSize.y/2 - 75,
      width = 150,
      height = 150,
    }, "mini", rl.GRAY)) {
      game.tileGrid = TileGrid {
        size = 6,
        hexagonSize = hexagonSize,
      }

      free_field(&game.tileGrid)
     
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

      force_start_next_turn(game)
      assign_tile_limits(game)
    }
    
    if (button(&game.ui, player.inputState, rl.Rectangle{
      x = player.inputState.screenSize.x/2 + 75,
      y = player.inputState.screenSize.y/2 + 75,
      width = 150,
      height = 150,
    }, "megarandom", rl.GRAY)) {
      game.tileTypeStats = [TileType]TileTypeStat{
        .Free         = {NA, NA, NA, NA, 0,  NA}, 
        .Blocked      = {NA, NA, NA, NA, NA, NA},
        .Land         = {NA, NA, NA, 1,  0,  NA},
        .Cannon       = {NA, NA, NA, 2,  0,  NA},
        .Shield       = {NA, NA, NA, 1,  0,  NA},
        .BlastTarget  = {NA, NA, NA, 2,  0,  NA},
        .Nuke         = {NA, NA, 2,  8,  0,  NA},
        .Mortar       = {1,  4,  1,  2,  0,  NA},
        .MortarTarget = {NA, NA, NA, 2,  0,  NA},
        .Telescope    = {NA, NA, NA, 2,  0,  NA},
        .Defense      = {2,  2,  NA, 4,  3,  NA},
      }

      game.tileGrid = TileGrid {
        size = 9,
        hexagonSize = hexagonSize,
      }
      
      randomize_field(&game.tileGrid)
     
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
      
      game.stats.energyPerRound = 10
      force_start_next_turn(game)
      assign_tile_limits(game)
    }
    
    if (button(&game.ui, player.inputState, rl.Rectangle{
      x = player.inputState.screenSize.x/2 + 75,
      y = player.inputState.screenSize.y/2 - 75,
      width = 150,
      height = 150,
    }, "big", rl.GRAY)) {
      game.tileTypeStats = [TileType]TileTypeStat{
        .Free         = {NA, NA, NA, NA, 0,  NA}, 
        .Blocked      = {NA, NA, NA, NA, NA, NA},
        .Land         = {NA, NA, NA, 1,  0,  NA},
        .Cannon       = {NA, NA, NA, 2,  0,  NA},
        .Shield       = {NA, NA, NA, 1,  0,  NA},
        .BlastTarget  = {NA, NA, NA, 2,  0,  NA},
        .Nuke         = {NA, NA, 2,  8,  0,  NA},
        .Mortar       = {1,  4,  1,  2,  0,  NA},
        .MortarTarget = {NA, NA, NA, 2,  0,  NA},
        .Telescope    = {NA, NA, NA, 2,  0,  NA},
        .Defense      = {2,  2,  NA, 4,  3,  NA},
      }

      game.tileGrid = TileGrid {
        size = 8,
        hexagonSize = hexagonSize,
      }
      
      free_field(&game.tileGrid)
     
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
      
      game.stats.energyPerRound = 10
      force_start_next_turn(game)
      assign_tile_limits(game)
    }
    
    if (button(&game.ui, player.inputState, rl.Rectangle{
      x = player.inputState.screenSize.x/2 - 225,
      y = player.inputState.screenSize.y/2 - 75,
      width = 150,
      height = 150,
    }, "random", rl.GRAY)) {
      game.tileTypeStats[.Nuke] = {NA, NA, 2, 5, NA, 1}

      game.tileGrid = TileGrid {
        size = 8,
        hexagonSize = hexagonSize,
      }

      randomize_field(&game.tileGrid)
     
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
      force_start_next_turn(game)
      assign_tile_limits(game) 
    }

    if (button(&game.ui, player.inputState, rl.Rectangle{
      x = player.inputState.screenSize.x/2 - 225,
      y = player.inputState.screenSize.y/2 - 125,
      width = 50,
      height = 50,
    }, "+1", rl.GRAY)) {
      game.seed += 1
      rand.reset(game.seed)
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
      if !virtual {
        rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{
          0, 0, 0, 150
        })
      }

      if game.winnerIdx == currentPlayerIndex {
        text_display(&game.ui, rl.Rectangle{
          x = player.inputState.screenSize.x/2 - 75,
          y = player.inputState.screenSize.y/2 - 120,
          width = 150,
          height = 150,
        }, "Victory", rl.WHITE, 50)
      } else {
        text_display(&game.ui, rl.Rectangle{
          x = player.inputState.screenSize.x/2 - 75,
          y = player.inputState.screenSize.y/2 - 120,
          width = 150,
          height = 150,
        }, "Defeat", rl.WHITE, 50)
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
        render_active_tile(game, player.inputState, currentPlayerIndex)
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
  app.gameInstance.seed = u64(app.network.lobby.clients[app.network.lobby.creatorIdx].endpoint.port)
  rand.reset(app.gameInstance.seed)

  app.playerCount = app.network.lobby.client_count
  app.playerIndex = get_client_player_idx(&app.network)
  
  app.gameInstance.playerCount = app.playerCount
  
  for i in 0..<app.playerCount {
    client := &app.network.lobby.clients[i]
    app.playerNames[i] = string(client.name_buf[:client.name_len])
    app.gameInstance.players[i].inputState = &app.network.lobby.inputStates[i]
  }  
  
  app.gameInstance.tileTypeStats = defaultTileTypeStats
  app.gameInstance.stats = defaultGameStats
 
  for playerName, i in app.playerNames {
    player := &app.gameInstance.players[i]

    player.color = playerColors[i]
    player.username = app.playerNames[i]
    player.selectedTileType = .Land
  }  
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
  rl.InitWindow(920, 800, "hexabomb")
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
