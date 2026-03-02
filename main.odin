package main
import "core:strconv"
import rl "vendor:raylib"
import "core:strings"
import "core:time"
import "core:os"
import vl "core:mem/virtual"
import "core:math/rand"

import "log"
import net "network"
import "ui"

import rn "base:runtime"

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

EditMode :: enum {
    Placing,
    Clicking,
}

DefaultTileStatsType :: enum {
    Mini,
    Big,
}

Player :: struct {
    tileLimits: [TileType]u8,
    playerState: PlayerState,
    color: rl.Color,
    selectedTileType: TileType,
    selectedPlayerIdx: u8,
    editMode: EditMode,
    energy: u16,
    username: string,
    activeTileId: u32,
    peeking: bool,
    editorStatsOpen: bool,
    tileCursorLocation: HalfGridPosition,
    selectedDefaultTileStats: DefaultTileStatsType,
    using frameContext: ^ui.FrameInfo,
    ui_buffer: ui.UI,
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
    .BlastTarget  = {NA, NA, 1,  1,  0,  NA},
    .Nuke         = {NA, NA, 1,  3,  0,  NA},
    .Mortar       = {1,  2,  1,  1,  0,  NA},
    .MortarTarget = {NA, NA, NA, 1,  0,  NA},
    .Telescope    = {NA, NA, NA, 1,  0,  NA},
    .Defense      = {2,  1,  NA, 2,  3,  NA},
    .BridgeStart  = {NA, NA, NA, 3,  NA, NA},
    .BridgeEnd    = {NA, NA, NA, 0,  NA, NA},
    .Landmine     = {NA, NA, 2,  2,  0,  NA},
}

defaultBigTileTypeStats := [TileType]TileTypeStat{
    .Free         = {NA, NA, NA, NA, 0,  NA},
    .Blocked      = {NA, NA, NA, NA, NA, NA},
    .Land         = {NA, NA, NA, 1,  0,  NA},
    .Cannon       = {NA, NA, NA, 2,  0,  NA},
    .Shield       = {NA, NA, NA, 1,  0,  NA},
    .BlastTarget  = {NA, NA, 1,  2,  0,  NA},
    .Nuke         = {NA, NA, 2,  8,  0,  NA},
    .Mortar       = {1,  4,  1,  2,  0,  NA},
    .MortarTarget = {NA, NA, NA, 2,  0,  NA},
    .Telescope    = {NA, NA, NA, 2,  0,  NA},
    .Defense      = {2,  2,  NA, 4,  3,  NA},
    .BridgeStart  = {NA, NA, NA, 3,  NA, NA},
    .BridgeEnd    = {NA, NA, NA, 0,  NA, NA},
    .Landmine     = {NA, NA, 2,  4,  0,  NA},
}

MapSpecficModifier :: enum {
    LandAhoy,
    Solo,
    Random,
    EnergyRush,
}

Modifier :: enum {
    Editor,
    OverrideModifiers,
}

map_modifiers := [MapSpecficModifier]string{
    .LandAhoy = "land ahoy",
    .Solo = "solo",
    .Random = "random",
    .EnergyRush = "rush",
}

nonmap_modifiers := [Modifier]string{
    .Editor = "editor",
    .OverrideModifiers = "override",
}

GameStats :: struct {
    energyPerRound: u16,
}

MAX_ENTITIES :: 32
MAX_PARTICLES :: 1024

MapState :: struct {
    stats: GameStats,
    tileTypeStats: [TileType]TileTypeStat,
    tileGrid: TileGrid,
    mapName: string,
    map_modifiers: bit_set[MapSpecficModifier],
}

Game :: struct {
    state: GameState,

    // Map State
    using map_state: MapState,
    non_map_modifiers: bit_set[Modifier],

    // Transient State
    saved_map_names: [][16]u8,
    saved_map_count: u16,
    
    playerCount: u8,
    players: [MAX_PLAYERS]Player,
    winnerIdx: u8,

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

    if .Solo in game.map_modifiers {
        update_solo_boss(game)
    }

    if .EnergyRush in game.map_modifiers {
        game.stats.energyPerRound += 1
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

update_game :: proc(game: ^Game, dt: f32, currentPlayerIndex: u8) {
    player := &game.players[currentPlayerIndex]
    trigger: ui.TriggerType

    if player.ui_buffer.inputMode == .Mouse{
        trigger, _ = ui.trigger()
    }

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
        game_endscreen(game, currentPlayerIndex)
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
                if .Editor in game.non_map_modifiers {
                    place_tile_editor(game, currentPlayerIndex)
                } else {
                    place_tile_game(game, currentPlayerIndex)
                }
            }
        case .Clicking:
            if .Update in player.behaviour {
                if .Editor not_in game.non_map_modifiers {
                    click_tile(game, currentPlayerIndex, currentPlayerIndex+1)
                } else {
                    click_tile(game, currentPlayerIndex, player.selectedPlayerIdx+1)
                }
            }

            active_tile_game_ui(game, currentPlayerIndex)
        }

        if .Editor in game.non_map_modifiers {
            editor_side_ui(game, currentPlayerIndex)
        }

        edit_map_stats_ui(game, currentPlayerIndex)
        ui_layout(game, currentPlayerIndex)

        if player.ui_buffer.inputMode != .Mouse {
            if ui.is_button_pressed(player.frameContext, .Semicolon) {
                ui.exit_capture_key_input()
            }
            if ui.is_button_pressed(player.frameContext, .SingleQuote) {
                player.ui_buffer.cursorLocation = {0, 0}
                ui.capture_key_input()
                player.editMode = .Clicking
                player.activeTileId = 0
            }
            //TODO: how do you know this is the correct capture? -- YOU DON'T!!
            if player.ui_buffer.inputMode == .CapturedKeyboard {
                if ui.is_button_pressed(player.frameContext, .W) {
                    player.tileCursorLocation += directions[.Down]
                }
                if ui.is_button_pressed(player.frameContext, .E) {
                    player.tileCursorLocation += directions[.RightDown]
                }
                if ui.is_button_pressed(player.frameContext, .Q) {
                    player.tileCursorLocation += directions[.LeftDown]
                }
                if ui.is_button_pressed(player.frameContext, .S) {
                    player.tileCursorLocation += directions[.Up]
                }
                if ui.is_button_pressed(player.frameContext, .D) {
                    player.tileCursorLocation += directions[.RightUp]
                }
                if ui.is_button_pressed(player.frameContext, .A) {
                    player.tileCursorLocation += directions[.LeftUp]
                }
                hover_tilegrid(&game.tileGrid, player)
            }
        } else if trigger != .NotActive {
            player.tileCursorLocation = get_tile_grid_pos(&game.tileGrid, player.frameContext.inputState.mousePos)
            hover_tilegrid(&game.tileGrid, player)
        }
    }
}

AppState :: enum {
    Connecting,
    Playing,
}

App :: struct {
    state: AppState,
    
    gameStartTime: time.Time,
    currentClientInputState: ui.InputState,    
    lastClientInputState: ui.InputState,    

    network: net.Network,
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
    
    load_map_entries(&app.gameInstance)
}

init_logs :: proc(app: ^App, clientName: string, clearlogs: bool) {
    log.init(clientName, true)

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
            frameContext: ui.FrameInfo
            
            if i != app.playerIndex {
                frameContext = ui.FrameInfo {
                    inputState = app.network.inputFrames[i],
                    lastInputState = app.network.prevInputFrames[i],
                    behaviour = { }
                }
            } else {
                frameContext = ui.FrameInfo {
                    inputState = app.network.currentInputFrameState,
                    lastInputState = app.network.lastInputFrameState,
                    behaviour = { .Draw }
                }    
            }

            if uptodate {
                frameContext.behaviour += { .Update }
            }

            player.ui_buffer.frameContext = &frameContext
            player.frameContext = &frameContext

            if frameContext.inputState.screenSize == {0, 0} {
                continue
            }

            ui.begin_ui(&player.ui_buffer, { 
                width = frameContext.inputState.screenSize.x, 
                height = frameContext.inputState.screenSize.y 
            })

            update_game(&app.gameInstance, dt, u8(i)) 
            
            ui.end_ui()
        }

        if uptodate {
            net.incrementFrameNumber(&app.network, &app.currentClientInputState)
        }

        rl.EndDrawing()
    case .Connecting:
        rl.BeginDrawing()
        rl.ClearBackground(rl.WHITE)

        ui.begin_ui(&app.ui, { 
            width = app.currentClientInputState.screenSize.x, 
            height = app.currentClientInputState.screenSize.y
        })

        app.ui.frameContext = &ui.FrameInfo{
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

        ui.end_ui()
    }    

    app.lastClientInputState = app.currentClientInputState
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
