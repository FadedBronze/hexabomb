package main
import "ui"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"
import "utils"
import net "network"
import la "core:math/linalg"
import "core:math/rand"

TileInfo :: struct{
    name: string,
    flags: bit_set[TileFlags],
}

tile_info := [TileType]TileInfo{
    .Blocked =      {"blocked",     {.Editor}},
    .Free =         {"free",        {.Editor}},
    .Land =         {"land",        {.Game, .Editor}},
    .Cannon =       {"cannon",      {.Game, .Editor}},
    .Shield =       {"shield",      {.Game, .Editor}},
    .Nuke =         {"nuke",        {.Game, .Editor, .Placeholder}},
    .Mortar =       {"mortar",      {.Game, .Editor}},
    .Telescope =    {"lookout",     {.Game, .Editor}},
    .Defense =      {"defense",     {.Game, .Editor}},
    .BridgeStart =  {"bridge",      {.Game, .Editor}},
    .Landmine =     {"landmine",    {.Game, .Editor}},
    .BridgeEnd =    {"",            {}},
    .BlastTarget =  {"",            {.Placeholder}},
    .MortarTarget = {"",            {.Placeholder}},
}

TileFlags :: enum {
    Editor,
    Game,
    Placeholder,
}

tile_availability := [TileType]bit_set[TileFlags]{
    .Blocked = {.Editor},
    .Free = {.Editor},
    .Cannon = {.Game, .Editor},
    .Land = {.Game, .Editor},
    .Shield = {.Game, .Editor},
    .Nuke = {.Game, .Editor},
    .Mortar = {.Game, .Editor},
    .Telescope = {.Game, .Editor},
    .Defense = {.Game, .Editor},
    .BridgeStart = {.Game, .Editor},
    .Landmine = {.Game, .Editor},
    .BlastTarget = {},
    .MortarTarget = {},
    .BridgeEnd = {},
}

ui_layout :: proc(game: ^Game, currentPlayerIndex: u8) {
    player := &game.players[currentPlayerIndex]

    ui.add_layout(ui.margin_all(10))
    ui.add_bounds({150, 75})

    {
        ui.add_layout(ui.FlexBox{
            gap = 10,
            direction = .Horizontal,
            corner = {.Top, .Left},
        })

        for tile in TileType {
            if .Editor in game.non_map_modifiers {
                if .Editor not_in tile_info[tile].flags {
                    continue
                }
            } else {
                if .Game not_in tile_info[tile].flags {
                    continue
                }
            }

            ui.add_bounds({80, 75})
            if (ui.button(tile_info[tile].name, player.color, id=tile_info[tile].name)) {
                //IDK yet play_audio("click.mp3")
                player.editMode = .Placing
                player.selectedTileType = tile
                player.activeTileId = 0
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
            corner = {},
            gap = 10,
        })

        if (.Editor in game.non_map_modifiers) {
            ui.add_bounds({150, 75})
            if (ui.button("save", player.color)) {
                buf: [16]u8

                for i in 0..<len(buf) {
                    buf[i] = u8(rand.float32() * f32('z'-'a') + f32('a'))
                }

                game.mapName = transmute(string)buf[:]
                save_map_data(game)
                game.mapName = ""
            }
            ui.pop_bounds()
        } else {
            ui.add_bounds({150, 75})
            if (ui.button( "end turn", player.color)) {
                start_next_turn(game, currentPlayerIndex)
            }
            ui.pop_bounds()
        }

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
            corner = {.Left},
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

game_selector_maps :: proc(game: ^Game, player: ^Player) {
    button_bounds := la.Vector2f32{80, 80}
    hexagonSize: i32 = 30

    ui.add_bounds(button_bounds)
    if (ui.button("mini", rl.GRAY)) {
        game.stats.energyPerRound = 3
        game.tileTypeStats = defaultTileTypeStats

        game.tileGrid = TileGrid {
            size = 6,
            hexagonSize = hexagonSize,
        }

        if .Random in game.map_modifiers {
            randomize_field(&game.tileGrid, game.map_random_context)
        } else {
            free_field(&game.tileGrid)
        }

        create_tile(game, 1, 1, {2, 2})
        create_tile(game, 2, 2, {-2, -2})

        force_start_next_turn(game)
        assign_tile_limits(game)
    }
    ui.pop_bounds()

    if game.playerCount == 1 {
        ui.add_bounds(button_bounds)
        if (ui.button("solo", rl.GRAY)) {
            game.stats.energyPerRound = 10
            game.tileTypeStats = defaultBigTileTypeStats

            game.tileGrid = TileGrid {
                size = 9,
                hexagonSize = hexagonSize,
            }

            if .Random in game.map_modifiers {
                randomize_field(&game.tileGrid, game.map_random_context)
            } else {
                free_field(&game.tileGrid)
            }

            create_tile(game, 1, 1, {0, 0})

            create_tile(game, 2, 2, {0, 8})
            create_tile(game, 2, 2, {0, -8})
            create_tile(game, 2, 2, {4, 0})
            create_tile(game, 2, 2, {-4, 0})

            game.map_modifiers += {.Solo}

            force_start_next_turn(game)
            assign_tile_limits(game)
        }
        ui.pop_bounds()
    }

    ui.add_bounds(button_bounds)
    if (ui.button("mega", rl.GRAY)) {
        game.tileTypeStats = defaultBigTileTypeStats
        game.stats.energyPerRound = 10

        game.tileGrid = TileGrid {
            size = 9,
            hexagonSize = hexagonSize,
        }

        if .Random in game.map_modifiers {
            randomize_field(&game.tileGrid, game.map_random_context)
        } else {
            free_field(&game.tileGrid)
        }

        create_tile(game, 1, 1, {3, 3})
        create_tile(game, 2, 2, {-3, -3})

        game.stats.energyPerRound = 10
        force_start_next_turn(game)
        assign_tile_limits(game)
    }
    ui.pop_bounds()
    
    ui.add_bounds(button_bounds)
    if (ui.button("big", rl.GRAY)) {
        game.tileTypeStats = defaultBigTileTypeStats
        game.stats.energyPerRound = 8

        game.tileGrid = TileGrid {
            size = 8,
            hexagonSize = hexagonSize,
        }

        if .Random in game.map_modifiers {
            randomize_field(&game.tileGrid, game.map_random_context)
        } else {
            free_field(&game.tileGrid)
        }

        create_tile(game, 1, 1, {3, 3})
        create_tile(game, 2, 2, {-3, -3})

        game.stats.energyPerRound = 10
        force_start_next_turn(game)
        assign_tile_limits(game)
    }
    ui.pop_bounds()

    for &mapname in game.saved_map_names[:game.saved_map_count] {
        mapname := transmute(string)mapname[:]

        ui.add_bounds(button_bounds)
        if (ui.button(mapname, rl.GRAY)) {
            buf: [32]u8
            path := utils.concatenate(buf[:], "./maps/", mapname)

            if (load_map_data(game, path)) {
                force_start_next_turn(game)
                assign_tile_limits(game)
            }
        }
        ui.pop_bounds()
    }
}

game_selector :: proc(game: ^Game, player: ^Player) {
    ui.flat_color(rl.Color{ 0, 0, 0, 20 })

    ui.add_layout(ui.FlexBox{
        gap = 10,
        corner = {.Left, .Top},
        direction = .Horizontal,
        spacing = .Centered,
    })

    ui.add_bounds({0.8, 1})
     
    ui.add_layout(ui.FlexBox{
        gap = 20,
        corner = {.Left, .Top},
        direction = .Vertical,
        spacing = .Centered,
    })

    ui.add_bounds({0.1, 20})
    ui.text_display("maps", rl.BLACK)
    ui.pop_bounds()
    
    ui.add_bounds({1, 0.4})
    ui.outline(rl.Color{ 0, 0, 0, 100 })
    ui.add_layout(ui.margin(10))

    ui.add_bounds({1, 1})
    ui.add_layout(ui.FlexBox{
        gap = 10,
        corner = {.Left, .Top},
    })
    
    game_selector_maps(game, player)
    
    ui.pop_layout()
    ui.pop_bounds()

    ui.pop_layout()
    ui.pop_bounds()

    ui.add_bounds({1, 70})
    ui.add_layout(ui.FlexBox{
        gap = 10,
        direction = .Vertical,
        corner = {.Top, .Left},
        spacing = .Linear,
    })

    for mode in MapSpecficModifier {
        render_modifier_toggle(&game.map_modifiers, map_modifiers, mode)
    }
    
    for mode in Modifier {
        render_modifier_toggle(&game.non_map_modifiers, nonmap_modifiers, mode)
    }
  
    ui.pop_layout()
    ui.pop_bounds()
    
    ui.pop_layout()
    ui.pop_bounds()

    ui.pop_layout()

    rl.DrawCircle(i32(player.inputState.mousePos.x), i32(player.inputState.mousePos.y), 12, rl.BLACK)
}

render_modifier_toggle :: proc(modifiers: ^bit_set[$T], names: [T]string, mode: T, loc := #caller_location) {
    buf: [32]u8
    str := strings.unsafe_string_to_cstring(utils.concatenate(buf[:], names[mode], "\x00")) 
    text_size := f32(rl.MeasureText(str, 22))

    ui.add_bounds({text_size + 50, 30})

    ui.add_layout(ui.FlexBox{
        gap = 10,
        corner = {.Left, .Top},
        direction = .Horizontal,
    })

    ui.add_bounds({30, 30})
    selected := mode in modifiers
    if ui.toggle(rl.BLACK, rl.GRAY, selected, id=names[mode], loc = loc) {
        if selected {
            modifiers^ -= {mode}
        } else {
            modifiers^ += {mode}
        }
    }
    ui.pop_bounds()

    ui.add_bounds({text_size, 30})
    ui.text_display(names[mode], rl.BLACK)
    ui.pop_bounds()

    ui.pop_layout()
    ui.pop_bounds()
}

update_network_interface :: proc(app: ^App) { 
    network := &app.network
    ui.flat_color(rl.Color{ 0, 0, 0, 20 })
    
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
            corner = {.Left, .Top}
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

active_tile_game_ui :: proc(game: ^Game, currentPlayerIndex: u8) {
    player := &game.players[currentPlayerIndex]
    inputState := player.inputState

    tile, pos := get_active_tile(&game.tileGrid, player)

    ui.add_layout(ui.margin_xy(10, 150))
    ui.add_bounds()

    ui.add_layout(ui.FlexBox{
        direction = .Vertical,
        corner = {.Top},
        gap = 5
    })
    
    if tile != nil && .Editor in game.non_map_modifiers {
        buf: [32]u8

        ui.add_bounds({150, 50})
        if ui.button("next player", player.color) {
            player.selectedPlayerIdx += 1
            player.selectedPlayerIdx %= MAX_PLAYERS

            tile.playerId = player.selectedPlayerIdx+1
            tile.visibility = {}
            tile.visibility[player.selectedPlayerIdx] = .VeryVisible
        }
        ui.pop_bounds()
    }

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

game_endscreen :: proc(game: ^Game, currentPlayerIndex: u8) {
    player := &game.players[currentPlayerIndex]
    //TODO -> fix the winner detection code before refactoring this

    if !player.peeking {
        ui.flat_color(rl.Color{ 0, 0, 0, 150 })
    }

    ui.add_layout(ui.margin_tblr(150, -50, 130, 130, relativity=.FromCenter))
    ui.add_bounds()
    
    if !player.peeking {
        if game.winnerIdx == currentPlayerIndex {
            ui.text_display("Victory", rl.WHITE, 50)
        } else {
            ui.text_display("Defeat", rl.WHITE, 50)
        }
    }

    ui.pop_bounds()
    ui.pop_layout()

    ui.add_layout(ui.margin_tblr(50, -150, 130, 130, relativity=.FromCenter))
    ui.add_bounds()

    ui.add_layout(ui.FlexBox{
        gap = 10,
        corner = {.Top, .Left},
        direction = .Horizontal,
        spacing = .Centered,
    })

    ui.add_bounds({100, 60})
    peeking := ui.held_button("peek", player.color)
    if .Update in player.behaviour {
        player.peeking = peeking
    }
    ui.pop_bounds()

    ui.add_bounds({100, 60})
    if !player.peeking {
        if (ui.button("continue", player.color)) {
            game.state = .GameSelector
        }
    }
    ui.pop_bounds()
    
    ui.pop_layout()

    ui.pop_bounds()
    ui.pop_layout()
}
