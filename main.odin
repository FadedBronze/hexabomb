package main
import "core:strconv"
import rl "vendor:raylib"
import la "core:math/linalg"
import "core:strings"
import "core:time"
import "core:os"
import vl "core:mem/virtual"
import "core:math/rand"

import "log"
import net "network"
import "ui"
import "utils"

import rn "base:runtime"

import sm "core:container/small_array"

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
    BridgeStart,
    BridgeEnd,
    Landmine,
}

Visibility :: [MAX_PLAYERS]enum {
    Invisible = 0,
    LandVisible = 1,
    Visible = 2,
    VeryVisible = 3,
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
    using uiFrameInfo: ^ui.FrameInfo,
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
    .BlastTarget  = {NA, NA, 1, 1,  0,  NA},
    .Nuke         = {NA, NA, 1,  3,  0,  NA},
    .Mortar       = {1,  2,  1,  1,  0,  NA},
    .MortarTarget = {NA, NA, NA, 1,  0,  NA},
    .Telescope    = {NA, NA, NA, 1,  0,  NA},
    .Defense      = {2,  1,  NA, 2,  3,  NA},
    .BridgeStart  = {NA, NA, NA, 3,  NA, NA},
    .BridgeEnd    = {NA, NA, NA, NA, NA, NA},
    .Landmine     = {NA, NA, 2,  2,  0,  NA},
}

defaultBigTileTypeStats := [TileType]TileTypeStat{
    .Free         = {NA, NA, NA, NA, 0,  NA},
    .Blocked      = {NA, NA, NA, NA, NA, NA},
    .Land         = {NA, NA, NA, 1,  0,  NA},
    .Cannon       = {NA, NA, NA, 2,  0,  NA},
    .Shield       = {NA, NA, NA, 1,  0,  NA},
    .BlastTarget  = {NA, NA, 1, 2,  0,  NA},
    .Nuke         = {NA, NA, 2,  8,  0,  NA},
    .Mortar       = {1,  4,  1,  2,  0,  NA},
    .MortarTarget = {NA, NA, NA, 2,  0,  NA},
    .Telescope    = {NA, NA, NA, 2,  0,  NA},
    .Defense      = {2,  2,  NA, 4,  3,  NA},
    .BridgeStart  = {NA, NA, NA, 3,  NA, NA},
    .BridgeEnd    = {NA, NA, NA, NA, NA, NA},
    .Landmine     = {NA, NA, 2,  4,  0,  NA},
}

GameMode :: enum {
    LandAhoy,
    Solo,
    Random,
}

gamemode_names := [GameMode]string{
    .LandAhoy = "land ahoy",
    .Solo = "solo",
    .Random = "random",
}

GameStats :: struct {
    energyPerRound: u16,
    gameMode: bit_set[GameMode],
}

MAX_ENTITIES :: 32
MAX_PARTICLES :: 1024

Game :: struct {
    state: GameState,

    tileTypeStats: [TileType]TileTypeStat,
    stats: GameStats,

    playerCount: u8,
    players: [MAX_PLAYERS]Player,
    winnerIdx: u8,

    tileGrid: TileGrid,

    using simulation: Simulation,

    rounds: u32,
    seed: u64,

    map_random_context: rn.Random_Generator,
}

playerColors := [4]rl.Color {
    rl.BLUE,
    rl.RED,
    rl.GREEN,
    rl.ORANGE,
}

format_cost_and_scaling :: proc(game: ^Game, tileType: TileType, bufstr: []u8) -> string {
    assert(len(bufstr)>=16)

    scalingCost := game.tileTypeStats[tileType].scalingCost
    scaling := game.tileTypeStats[tileType].scaling
    buf: [4]u8
    buf2: [4]u8

    return utils.concatenate(bufstr[:], 
        "+",
        strconv.write_uint(buf[:], u64(scaling), 10), 
        " for ", 
        strconv.write_uint(buf2[:], u64(scalingCost), 10), 
        "e"
    )
}

click_tile :: proc(game: ^Game, currentPlayerIndex: u8) {
    player := &game.players[currentPlayerIndex]

    within_bounds, halfgrid := get_tile_grid_pos_safe(&game.tileGrid, player.inputState.mousePos)

    if !within_bounds {
        return
    }

    hovered_tile := get_tile(&game.tileGrid, halfgrid)

    if hovered_tile.playerId == 0 {
        return
    }

    if ui.is_left_button_pressed(player.uiFrameInfo) {
        if rl.IsKeyDown(.LEFT_SHIFT) {
            log.msg("debug", hovered_tile)
        }

        if hovered_tile.type == .Cannon && hovered_tile.playerId - 1 == currentPlayerIndex {
            player.activeTileId = get_tile_id(halfgrid)

            player.editMode = .Placing
            player.selectedTileType = .BlastTarget
        }

        if (hovered_tile.type == .Mortar || hovered_tile.type == .Shield || hovered_tile.type == .Defense) && hovered_tile.playerId - 1 == currentPlayerIndex {
            player.activeTileId = get_tile_id(halfgrid)
        }
    }
}

active_tile_ui :: proc(game: ^Game, currentPlayerIndex: u8) {
    player := &game.players[currentPlayerIndex]
    inputState := player.inputState

    tile, pos := get_active_tile(&game.tileGrid, player)

    ui.add_layout(ui.margin_xy(10, 150))
    ui.add_bounds()

    ui.add_layout(ui.FlexBox{
        direction = .Vertical,
        corner = .TopRight,
        gap = 5
    })

    if tile != nil && tile.type == .Mortar {
        buf: [32]u8

        ui.add_bounds({150, 50})
        if (ui.button(
            format_cost_and_scaling(
                game, 
                .Mortar, 
                buf[:]), 
                player.color
            ) && player.energy >= auto_cast game.tileTypeStats[.Mortar].scalingCost
        ) {
            tile.damage += game.tileTypeStats[.Mortar].scaling
            player.energy -= auto_cast game.tileTypeStats[.Mortar].scalingCost
        }
        ui.pop_bounds()

        ui.add_bounds({150, 50})
        if (ui.button("fire", player.color)) {
            player.editMode = .Placing
            player.selectedTileType = .MortarTarget
        }
        ui.pop_bounds()
    }

    if tile != nil && tile.type == .Defense {
        buf: [32]u8

        ui.add_bounds({150, 50})
        if (ui.button(format_cost_and_scaling(game, .Defense, buf[:]), player.color) && player.energy >= auto_cast game.tileTypeStats[.Defense].scalingCost) {
            tile.durability += game.tileTypeStats[.Defense].scaling
            player.energy -= auto_cast game.tileTypeStats[.Defense].scalingCost
        }
        ui.pop_bounds()
    }

    if tile != nil && tile.type == .Shield {
        ui.add_bounds({150, 50})
        if (ui.button("rotate", player.color)) {
            tile.direction = HexDirection((u8(tile.direction)+1)%6)
        }
        ui.pop_bounds()
    }
    
    ui.pop_layout()

    ui.pop_bounds()
    ui.pop_layout()
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

next_to_own_territory :: proc(game: ^Game, currentPlayerIndex: u8, halfGridPos: HalfGridPosition) -> bool {
    own_territory :: proc(game: ^Game, currentPlayerIndex: u8, tile: ^Tile) -> bool {
        player := &game.players[currentPlayerIndex]
        return tile.playerId - 1 == currentPlayerIndex && tile.type != .Blocked && tile.type != .Free
    }

    return test_adjacent_cell(game, currentPlayerIndex, halfGridPos, own_territory)
}

place_tile :: proc(game: ^Game, currentPlayerIndex: u8) {
    player := &game.players[currentPlayerIndex]

    if !ui.is_left_button_pressed(player.uiFrameInfo) {
        return
    }

    within_bounds, halfgridPos := get_tile_grid_pos_safe(&game.tileGrid, player.inputState.mousePos)

    if !within_bounds {
        return
    }

    tile := get_tile(&game.tileGrid, halfgridPos)

    if tile.type == .Blocked {
        return
    }

    activeTile, activeTileHalfgridPos := get_active_tile(&game.tileGrid, player)
    nextToActiveTile, dir := next_to(halfgridPos, activeTileHalfgridPos)

    switch player.selectedTileType {
    case .BridgeStart:
        if next_to_own_territory(game, currentPlayerIndex, halfgridPos) && pay_active_tile_cost(game, player) {
            create_player_land(game, currentPlayerIndex+1, halfgridPos)
            get_tile(&game.tileGrid, halfgridPos).type = .BridgeStart
            player.selectedTileType = .BridgeEnd
        }
    case .BridgeEnd:
        valid := false

        for direction in directions {
            for i in 0..<4 {
                tile := get_tile(&game.tileGrid, halfgridPos + direction * i16(i))
                if tile.type == .BridgeStart {
                    tile.type = .Land
                    valid = true
                }
            }
        }

        if valid {
            create_player_land(game, currentPlayerIndex+1, halfgridPos)
        }
    case .Nuke:
        if pay_active_tile_cost(game, player) {
            add_entity(game, currentPlayerIndex, halfgridPos, SimulationEntity {
                damage = game.tileTypeStats[.BlastTarget].cost
            }, EntityType.Nuke)
            
            add_particle(game, &explosion, opts={halfgridPos})
        }
    case .MortarTarget:
        if pay_active_tile_cost(game, player) {
            add_entity(game, currentPlayerIndex, halfgridPos, SimulationEntity {
                damage = activeTile.damage
            }, EntityType.MortarShot)

            add_particle(game, &explosion, opts={halfgridPos})

            player.activeTileId = 0
            player.editMode = .Clicking
        }
    case .BlastTarget:
        if nextToActiveTile && pay_active_tile_cost(game, player) {
            add_cannonball(game, activeTileHalfgridPos, halfgridPos, currentPlayerIndex, dir)

            player.activeTileId = 0
            player.editMode = .Clicking
        }
    case .Land:
        if tile.type != .Land && next_to_own_territory(game, currentPlayerIndex, halfgridPos) && pay_active_tile_cost(game, player) {
            create_player_land(game, currentPlayerIndex+1, halfgridPos)
        }
    case .Cannon, .Mortar, .Shield, .Defense, .Landmine, .Telescope:
        if tile.type == .Land && tile.playerId == currentPlayerIndex+1 && pay_active_tile_cost(game, player) {
            tile.visibility[currentPlayerIndex] = .VeryVisible
            tile.playerId = currentPlayerIndex + 1
            tile.type = player.selectedTileType
            tile.createdRound = u8(game.rounds)
            tile.durability = game.tileTypeStats[tile.type].durability

            #partial switch player.selectedTileType {
            case .Telescope:
                for dir in directions {
                    pos := halfgridPos

                    for within_game_bounds(game, pos) {
                        pos += dir

                        get_tile(&game.tileGrid, pos).visibility[currentPlayerIndex] = .VeryVisible
                    }
                }
            case .Mortar:
                tile.damage = game.tileTypeStats[.Mortar].damage
            case .Cannon, .Shield, .Defense, .Landmine:
            case:
                unreachable()
            }
        }
    case .Blocked, .Free:
        unreachable()
    }
}

randomDirection :: proc() -> HexDirection {
    return HexDirection(rand.float32() * 6)
}

update_solo_boss :: proc (game: ^Game) {
    fieldIterator: FieldIterator
    for {
        tile := iterate_field(&fieldIterator, &game.tileGrid)
        pos := get_position(&fieldIterator)

        if tile == nil {
            return
        }

        if tile.playerId != 2 {
            continue
        }

        if tile.createdRound == u8(game.rounds) {
            continue
        }

        for dir in directions {
            newpos := pos + dir
            newtile := get_tile(&game.tileGrid, newpos)

            if !within_game_bounds(game, newpos) {
                continue
            }

            if newtile.type == .Blocked {
                continue
            }

            newtile.type = random_tile_type({
                {tile = .Free, chanceRatio = 2},
                {tile = .Shield, chanceRatio = 2},
                {tile = .Defense, chanceRatio = 1},
                {tile = .Land, chanceRatio = 3},
                {tile = .Landmine, chanceRatio = 2},
            }, game.map_random_context)

            if newtile.type != .Free {
                newtile.playerId = 2
            }
            newtile.createdRound = u8(game.rounds)
        }
    }
}

force_start_next_turn :: proc (game: ^Game) {
    crown_winner(game)

    if .Solo in game.stats.gameMode {
        update_solo_boss(game)
    }

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

    if all_done {
        log.msg("debug", "All players confirmed end turn")
    }

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

button_names := [TileType]string{
    .Blocked = "",
    .Cannon = "cannon",
    .Land = "land",
    .Free = "",
    .Shield = "shield",
    .BlastTarget = "",
    .Nuke = "nuke",
    .Mortar = "mortar",
    .MortarTarget = "",
    .Telescope = "lookout",
    .Defense = "defense",
    .BridgeStart = "bridge",
    .BridgeEnd = "",
    .Landmine = "landmine",
}

ui_layout :: proc(game: ^Game, currentPlayerIndex: u8) {
    player := &game.players[currentPlayerIndex]

    ui.add_layout(ui.margin_all(10))
    ui.add_bounds({150, 75})

    {
        ui.add_layout(ui.FlexBox{
            gap = 10,
            direction = .Horizontal,
            corner = .TopLeft,
        })

        for tile in TileType {
            if button_names[tile] == "" {
                continue
            }

            ui.add_bounds({80, 75})
            if (ui.button(button_names[tile], player.color, id=button_names[tile])) {
                //IDK yet play_audio("click.mp3")
                player.editMode = .Placing
                player.selectedTileType = tile
            }
            ui.pop_bounds()
        }

        ui.add_bounds({80, 75})
        if (ui.button("click", player.color)) {
            player.editMode = .Clicking
        }
        ui.pop_bounds()

        ui.pop_layout()
    }

    {
        ui.add_layout(ui.FlexBox {
            direction = .Horizontal,
            corner = .BottomRight,
            gap = 10,
        })

        ui.add_bounds({150, 75})
        if (ui.button( "end turn", player.color)) {
            start_next_turn(game, currentPlayerIndex)
        }
        ui.pop_bounds()

        ui.add_bounds({150, 75})
        if (ui.button("lobby", player.color)) {
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
        ui.pop_bounds()

        ui.pop_layout()
    }

    {
        ui.add_layout(ui.FlexBox{ direction = .Horizontal,
            corner = .BottomLeft,
        })

        {
            buf: [8]u8
            ui.add_bounds({ 20, 20 })
            ui.text_display(strconv.write_int(buf[:], i64(game.rounds), 10), rl.BLACK)
            ui.pop_bounds()
        }

        {
            buf: [8]u8
            str := strconv.write_int(buf[:], i64(player.energy), 10)
            buf[len(str)] = 'e'

            ui.add_bounds({ 40, 20 })
            ui.text_display(cast(string)buf[:], rl.BLACK)
            ui.pop_bounds()
        }

        cost := game.tileTypeStats[player.selectedTileType].cost
        if cost != NA {
            buf: [8]u8
            buf[0] = '-'
            str := strconv.write_int(buf[1:], i64(cost), 10)
            buf[len(str)+1] = 'e'

            ui.add_bounds({ 40, 20 })
            ui.text_display(cast(string)buf[:], rl.RED)
            ui.pop_bounds()
        }

        {
            buf: [32]u8
            str: string

            if player.tileLimits[player.selectedTileType] != NA {
                str = strconv.write_int(buf[:], i64(player.tileLimits[player.selectedTileType]), 10)
            } else {
                str = "--"
                copy(buf[:], str)
            }

            copy(buf[len(str):], "")
            ui.add_bounds({ 40, 20 })
            ui.text_display(cast(string)buf[:len(str)+5], rl.BLACK)
            ui.pop_bounds()
        }

        ui.add_bounds({20, 20})
        ui.text_display(player.username, player.color)
        ui.pop_bounds()

        ui.pop_layout()
    }

    ui.pop_bounds()
    ui.pop_layout()
}

crown_winner :: proc(game: ^Game) {
    playerExists: [MAX_PLAYERS]bool = {}

    fieldIterator: FieldIterator

    for {
        tile := iterate_field(&fieldIterator, &game.tileGrid)

        if tile == nil {
            break
        }

        if tile.playerId == 0 {
            continue
        }

        playerExists[tile.playerId - 1] = true
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

get_position :: proc(iter: ^FieldIterator) -> HalfGridPosition {
    x := iter.j - HALF_MAX_GRID_SIZE
    y := iter.i - HALF_MAX_GRID_SIZE
    return {x, y}
}

random_tile_type :: proc(randomSelection: []struct{
    tile: TileType,
    chanceRatio: u8,
}, generator: rn.Random_Generator) -> (type: TileType) {
    totalRatio: u8 = 0

    for selection in randomSelection {
        totalRatio += selection.chanceRatio
    }

    roll := u8(rand.float32(gen = generator) * f32(totalRatio))

    i := u8(0)
    for selection in randomSelection {
        if roll >= i && roll < i + selection.chanceRatio {
            type = selection.tile
            break;
        }

        i += selection.chanceRatio
    }

    return type
}

randomize_field :: proc(tileGrid: ^TileGrid, generator: rn.Random_Generator) {
    fieldIterator: FieldIterator
    for {
        if tile := iterate_field(&fieldIterator, tileGrid); tile != nil {
            tile.type = random_tile_type({
                {tile = .Free, chanceRatio = 2},
                {tile = .Blocked, chanceRatio = 1}
                }, generator)
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

create_player_land :: proc(game: ^Game, id: u8, haldGridPos: HalfGridPosition) {
    tile := get_tile(&game.tileGrid, haldGridPos)

    tile^ = Tile {
        playerId = id,
        type = .Land,
        createdRound = u8(game.rounds),
        durability = game.tileTypeStats[tile.type].durability,
        visibility = {},
    }

    if id != 0 {
        tile.visibility[id-1] = .VeryVisible
    }

    for dir in directions {
        for i in 1..<i16(3) {
            pos := haldGridPos + dir * i
            nextTile := get_tile(&game.tileGrid, pos)

            if nextTile.playerId != 0 {
                their_visibility := &tile.visibility[nextTile.playerId-1]

                if within_game_bounds(game, pos) && their_visibility^ < .LandVisible {
                    their_visibility^ = .LandVisible
                }
            }

            if id != 0 {
                visibility := &nextTile.visibility[id - 1]

                if within_game_bounds(game, pos) && visibility^ < .LandVisible {
                    visibility^ = .LandVisible
                }
            }
        }
    }
}

game_selector :: proc(game: ^Game, player: ^Player) {
    hexagonSize: i32 = 30

    ui.add_layout(ui.margin_xy(320, 170, relativity=.FromCenter))
    ui.add_bounds()

    ui.add_layout(ui.FlexBox{
        gap = 10
    })

    ui.add_bounds({150, 150})
    if (ui.button("mini", rl.GRAY)) {
        game.stats.energyPerRound = 3
        game.tileTypeStats = defaultTileTypeStats

        game.tileGrid = TileGrid {
            size = 6,
            hexagonSize = hexagonSize,
        }

        if .Random in game.stats.gameMode {
            randomize_field(&game.tileGrid, game.map_random_context)
        } else {
            free_field(&game.tileGrid)
        }

        create_player_land(game, 1, {2, 2})
        create_player_land(game, 2, {-2, -2})

        force_start_next_turn(game)
        assign_tile_limits(game)
    }
    ui.pop_bounds()

    if game.playerCount == 1 {
        ui.add_bounds({150, 150})
        if (ui.button("solo", rl.GRAY)) {
            game.stats.energyPerRound = 10
            game.tileTypeStats = defaultBigTileTypeStats

            game.tileGrid = TileGrid {
                size = 9,
                hexagonSize = hexagonSize,
            }

            if .Random in game.stats.gameMode {
                randomize_field(&game.tileGrid, game.map_random_context)
            } else {
                free_field(&game.tileGrid)
            }

            create_player_land(game, 1, {0, 0})

            create_player_land(game, 2, {0, 8})
            create_player_land(game, 2, {0, -8})
            create_player_land(game, 2, {4, 0})
            create_player_land(game, 2, {-4, 0})

            game.stats.gameMode += {.Solo}

            force_start_next_turn(game)
            assign_tile_limits(game)
        }
        ui.pop_bounds()
    }

    ui.add_bounds({150, 150})
    if (ui.button("mega", rl.GRAY)) {
        game.tileTypeStats = defaultBigTileTypeStats
        game.stats.energyPerRound = 10

        game.tileGrid = TileGrid {
            size = 9,
            hexagonSize = hexagonSize,
        }

        if .Random in game.stats.gameMode {
            randomize_field(&game.tileGrid, game.map_random_context)
        } else {
            free_field(&game.tileGrid)
        }

        create_player_land(game, 1, {3, 3})
        create_player_land(game, 2, {-3, -3})

        game.stats.energyPerRound = 10
        force_start_next_turn(game)
        assign_tile_limits(game)
    }
    ui.pop_bounds()

    ui.add_bounds({150, 150})
    if (ui.button("big", rl.GRAY)) {
        game.tileTypeStats = defaultBigTileTypeStats
        game.stats.energyPerRound = 8

        game.tileGrid = TileGrid {
            size = 8,
            hexagonSize = hexagonSize,
        }

        if .Random in game.stats.gameMode {
            randomize_field(&game.tileGrid, game.map_random_context)
        } else {
            free_field(&game.tileGrid)
        }

        create_player_land(game, 1, {3, 3})
        create_player_land(game, 2, {-3, -3})

        game.stats.energyPerRound = 10
        force_start_next_turn(game)
        assign_tile_limits(game)
    }
    ui.pop_bounds()

    ui.pop_layout()

    ui.pop_bounds()
    ui.pop_layout()

    ui.add_layout(ui.margin_xy(320, 380, relativity=.FromCenter))
    ui.add_bounds()

    ui.add_layout(ui.FlexBox{
        gap = 10,
        direction = .Horizontal,
        corner = .BottomLeft,
    })

    for mode in GameMode {
        ui.add_bounds({30, 30})
        selected := mode in game.stats.gameMode

        if ui.toggle(rl.PINK, rl.GRAY, selected, id=u64(mode)) {
            if selected {
                game.stats.gameMode -= {mode}
            } else {
                game.stats.gameMode += {mode}
            }
        }
        ui.pop_bounds()

        ui.add_bounds({90, 20})
        ui.text_display(gamemode_names[mode], rl.BLACK)
        ui.pop_bounds()
    }
  
    ui.pop_layout()

    ui.pop_bounds()
    ui.pop_layout()

    rl.DrawCircle(i32(player.inputState.mousePos.x), i32(player.inputState.mousePos.y), 12, rl.BLACK)
}

update_game :: proc(game: ^Game, dt: f32, currentPlayerIndex: u8) {
    player := &game.players[currentPlayerIndex]

    if game.state != .GameSelector {
        if .Update in player.behaviour {
            update_tilegrid_offset(&game.tileGrid, &player.inputState)
        }

        if .Draw in player.behaviour {
            render_gameboard(game, currentPlayerIndex)
        }
    }
    
    switch game.state {
    case .GameSelector:
        game_selector(game, player)
    case .Winner:
        //TODO -> fix the winner detection code before refactoring this

        //within_button := ui.within_button(rl.Rectangle{
        //    x = player.inputState.screenSize.x/2 - 100,
        //    y = player.inputState.screenSize.y/2 - 0,
        //    width = 100,
        //    height = 40,
        //}, "peek", player.color)

        //if (!within_button || player.inputState.leftButton == .Up) {
        //    if .Draw in player.behaviour {
        //        rl.DrawRectangle(0, 0, auto_cast player.inputState.screenSize.x, auto_cast player.inputState.screenSize.y, rl.Color{
        //            0, 0, 0, 150
        //        })
        //    }

        //    if game.winnerIdx == currentPlayerIndex {
        //        ui.text_display(player.uiFrameInfo, rl.Rectangle{
        //            x = player.inputState.screenSize.x/2 - 75,
        //            y = player.inputState.screenSize.y/2 - 120,
        //            width = 150,
        //            height = 150,
        //        }, "Victory", rl.WHITE, 50)
        //    } else {
        //        ui.text_display(player.uiFrameInfo, rl.Rectangle{
        //            x = player.inputState.screenSize.x/2 - 75,
        //            y = player.inputState.screenSize.y/2 - 120,
        //            width = 150,
        //            height = 150,
        //        }, "Defeat", rl.WHITE, 50)
        //    }

        //    if (ui.button(rl.Rectangle{
        //        x = player.inputState.screenSize.x/2 - 0,
        //        y = player.inputState.screenSize.y/2 - 0,
        //        width = 100,
        //        height = 40,
        //    }, "continue", player.color)) {
        //        game.state = .GameSelector
        //    }
        //}
    case .Paused:
        ui.add_layout(ui.margin_xy(75, 75, relativity=.FromCenter))
        ui.add_bounds()
        play := ui.button("play", rl.GRAY)
        ui.pop_bounds()
        ui.pop_layout()

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
            if .Update in player.behaviour {
                place_tile(game, currentPlayerIndex)
            }
        case .Clicking:
            if .Update in player.behaviour {
                click_tile(game, currentPlayerIndex)
            }
            active_tile_ui(game, currentPlayerIndex)
        }

        ui_layout(game, currentPlayerIndex)
        hover_tilegrid(&game.tileGrid, player)
    }
}

AppState :: enum {
    Connecting,
    Playing,
}

App :: struct {
    state: AppState,
    
    fuzzInputTest: bool,

    gameStartTime: time.Time,
    currentClientInputState: ui.InputState,    
    lastClientInputState: ui.InputState,    

    network: net.Network(ui.InputState),
    gameInstance: Game,

    playerNames: [MAX_PLAYERS]string,
    playerCount: u8,
    playerIndex: u8,
    
    ui: ui.UI,
    audio: Audio,
}

init_game :: proc(app: ^App) {
    app.gameInstance.seed = u64(app.network.lobby.clients[app.network.lobby.creatorIdx].endpoint.port)

    app.gameInstance.map_random_context = rn.default_random_generator()
    rand.reset(app.gameInstance.seed, gen = app.gameInstance.map_random_context)

    app.playerCount = app.network.lobby.clientCount
    app.playerIndex = net.get_client_player_idx(&app.network)

    app.gameInstance.playerCount = app.playerCount

    for i in 0..<app.playerCount {
        client := &app.network.lobby.clients[i]
        app.playerNames[i] = client.name
    }

    app.gameInstance.tileTypeStats = defaultTileTypeStats

    for playerName, i in app.playerNames {
        player := &app.gameInstance.players[i]

        player.color = playerColors[i]
        player.username = app.playerNames[i]
        player.selectedTileType = .Land
    }
}

init_logs :: proc(app: ^App, clientName: string, clearlogs: bool) {
    log.init(clientName)

    if !clearlogs {
        log.msg("debug", "New Session")
        log.msg("error", "New Session")
        log.msg("network", "New Session")
        log.msg("input", "New Session")
    } else {
        log.clear("debug")
        log.clear("error")
        log.clear("network")
        log.clear("input")
    }
}

CLIArgs :: struct {
    port: int, 
    singleMachineTesting: bool, 
    clearlogs: bool, 
    username: string, 
    throttlems: int
}

parse_cli_args :: proc() -> (cliArgs: CLIArgs) {
    cliArgs.port = 6969

    for arg in os.args {
        ok: bool

        if strings.has_prefix(arg, "--port=") {
            cliArgs.port, ok = strconv.parse_int(strings.trim_prefix(arg, "--port="))
        }

        if strings.has_prefix(arg, "--clientname=") {
            cliArgs.username = strings.trim_prefix(arg, "--clientname=")
        }
        
        if strings.has_prefix(arg, "--local") {
            cliArgs.singleMachineTesting = true
        }

        if strings.has_prefix(arg, "--clearlogs") {
            cliArgs.clearlogs = true
        }   
    }

    return cliArgs
}

init_app :: proc(app: ^App, cliArgs: ^CLIArgs) {
    init_logs(app, cliArgs.username, cliArgs.clearlogs)

    log.msg("debug", "single machine testing:", cliArgs.singleMachineTesting)

    if (!net.init(&app.network, cliArgs.port, cliArgs.singleMachineTesting)) {
        app.state = .Playing
        net.create_local_lobby(&app.network, "my lobby")
    }    

    ui.init(&app.ui)
    rl.InitAudioDevice()
    init_audio("./sfx/", &app.audio)

    play_audio("music.mp3")
    
    net.incrementFrameNumber(&app.network, &app.currentClientInputState)
}

update_app :: proc(app: ^App, dt: f32) {
    frameArena: vl.Arena
    
    if err := vl.arena_init_growing(&frameArena); err != nil {
        log.msg("error", err)
        assert(false)
    }
    
    defer vl.arena_destroy(&frameArena)
    
    context.temp_allocator = vl.arena_allocator(&frameArena)
    
    app.currentClientInputState = ui.get_input_state()

    app.fuzzInputTest = rl.IsKeyPressed(.T) ? !app.fuzzInputTest : app.fuzzInputTest

    if app.fuzzInputTest {
        app.currentClientInputState = ui.generate_random_input({920, 800})
    }
    
    ui.begin_ui({ 
        width = f32(rl.GetScreenWidth()), 
        height = f32(rl.GetScreenHeight()) 
    })

    switch app.state {
    case .Playing:
        if (!net.broadcast_input_state(&app.network)) {
            app.network.state = .Failed
            app.state = .Connecting
        }

        if (!net.recieve_messages(&app.network)) {
            app.network.state = .Failed
            app.state = .Connecting
        } 
        
        uptodate := net.all_inputs_uptodate(&app.network)
        
        rl.BeginDrawing()
        rl.ClearBackground(rl.WHITE)
        
        if app.network.state == .Failed {
            app.state = .Connecting
        }

        for i in 0..<app.playerCount {
            player := &app.gameInstance.players[i]
            frameInfo: ui.FrameInfo
            
            if i != app.playerIndex {
                frameInfo = ui.FrameInfo {
                    inputState = app.network.inputFrames[i],
                    lastInputState = app.network.prevInputFrames[i],
                    behaviour = { }
                }
            } else {
                frameInfo = ui.FrameInfo {
                    inputState = app.network.currentInputFrameState,
                    lastInputState = app.network.lastInputFrameState,
                    behaviour = { .Draw }
                }    
            }

            if uptodate {
                frameInfo.behaviour += { .Update }
            }
            
            app.ui.frameInfo = &frameInfo
            player.uiFrameInfo = &frameInfo
            update_game(&app.gameInstance, dt, u8(i)) 
        }

        if uptodate {
            net.incrementFrameNumber(&app.network, &app.currentClientInputState)
        }

        rl.EndDrawing()
    case .Connecting:
        rl.BeginDrawing()
        rl.ClearBackground(rl.WHITE)

        app.ui.frameInfo = &ui.FrameInfo{
            inputState = app.currentClientInputState,
            lastInputState = app.lastClientInputState,
            behaviour = { .Draw, .Update }
        }
        update_network_interface(app)    
        
        rl.EndDrawing()
        
        if app.network.state == .Connected {
            app.state = .Playing
            init_game(app)
        }
    }
    
    ui.end_ui()

    app.lastClientInputState = app.currentClientInputState
}

update_network_interface :: proc(app: ^App) { 
    network := &app.network
    
    ui.flat_color(rl.Color{ 0, 0, 0, 150 })

    switch network.state {
    case .Failed:
        ui.add_layout(ui.margin_xy(75, 75, relativity=.FromCenter))
        ui.add_bounds()
        try_again := ui.button("Network error: try again?", rl.GRAY)
        ui.pop_bounds()
        ui.pop_layout()

        if try_again {
            network.state = .InLobby
        }
    case .Connected:
    case .WaitingForLobbyInfo:
        if (!net.recieve_messages(network)) {
            network.state = .Failed
            return
        }
    case .InLobby:
        if (!net.recieve_messages(network)) {
            network.state = .Failed
            return
        }

        buf: [2]u8
        buf[0] = network.lobby.clientCount + '0'
        buf[1] = '\x00'
        rl.DrawText(transmute(cstring)raw_data(buf[:]), 10, 10, 24, rl.WHITE)

        if net.client_is_lobby_master(network) {
            if !net.broadcast_my_lobby_entry(network) {
                network.state = .Failed
                return
            }

            net.recieve_discovery_messages(network)

            ui.add_layout(ui.margin_xy(75, 75, relativity=.FromCenter))
            ui.add_bounds()
            start := ui.button("start", rl.GRAY)
            ui.pop_bounds()
            ui.pop_layout()

            if start {
                network.state = .Connected
                if !net.broadcast_game_start(network) {
                    network.state = .Failed
                    return
                } 
            }    
        }
    case .Connecting:
        if (!net.recieve_discovery_messages(network)) {
            network.state = .Failed
            return
        }

        ui.add_layout(ui.margin_xy(75, 150, relativity=.FromCenter))

        ui.add_bounds()
        
        ui.add_layout(ui.FlexBox {
            gap = 10,
            direction = .Vertical,
        })

        lobby_count := network.lobbyEntries.len

        for i in 0..<u64(4) {
            buf: [32]u8
            ui.add_bounds({ 150, 50 })
            if ui.button(
                lobby_count > int(i) ? net.fmt_lobby_name(buf[:], &network.lobbyEntries.data[i]) : "--", 
                rl.GRAY, 
                id = i
            ) && lobby_count > int(i) {
                if (!net.request_join_lobby(network, network.lobbyEntries.data[i].endpoint)) {
                    network.state = .Failed
                    return
                }
                network.state = .WaitingForLobbyInfo
            }
            ui.pop_bounds()
        }

        ui.add_bounds({150, 50})
        create_room := ui.button("create room", rl.GRAY)
        ui.pop_bounds()
        ui.pop_layout()

        ui.pop_bounds()
        ui.pop_layout()

        if (create_room) {
            net.create_lobby(network, "the room")
            network.state = .InLobby
        }
    }        
}

main :: proc() {
    arena: vl.Arena
    
    if err := vl.arena_init_growing(&arena); err != nil {
        log.msg("error", err)
        assert(false)
    }
    
    defer vl.arena_destroy(&arena)
    
    context.allocator = vl.arena_allocator(&arena)
    
    cliArgs := parse_cli_args()

    rl.InitWindow(920, 800, "hexabomb")
    rl.SetWindowState({.WINDOW_RESIZABLE})

    if cliArgs.username == "player_1" {
        rl.SetWindowPosition(30, 40)
    }

    if cliArgs.username == "player_2" {
        rl.SetWindowPosition(970, 40)
    }

    app: App
    init_app(&app, &cliArgs)
    
    for !rl.WindowShouldClose() {
        update_app(&app, rl.GetFrameTime())
        update_audio()
    }
}
