package main

import "core:encoding/cbor"
import "core:os"
import "core:strconv"

import "log"
import "ui"
import "utils"

import rl "vendor:raylib"

editor_side_ui :: proc(game: ^Game, currentPlayerIndex: u8) {
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

    if tile == nil {
        increment_widget("count", player.color, &game.tileTypeStats[player.selectedTileType].limit)

        if defaultTileTypeStats[player.selectedTileType].cost != NA {
            increment_widget("cost", player.color, &game.tileTypeStats[player.selectedTileType].cost)
        }
        if defaultTileTypeStats[player.selectedTileType].durability != NA {
            increment_widget("durability", player.color, &game.tileTypeStats[player.selectedTileType].durability)
        }
        if defaultTileTypeStats[player.selectedTileType].scaling != NA {
            increment_widget("scaling", player.color, &game.tileTypeStats[player.selectedTileType].scaling)
        }
        if defaultTileTypeStats[player.selectedTileType].scalingCost != NA {
            increment_widget("scalingCost", player.color, &game.tileTypeStats[player.selectedTileType].scalingCost)
        }
    }

    if tile != nil && tile.type == .Land {
        buf: [32]u8

        ui.add_bounds({150, 50})
        if ui.button("next player", player.color) {
            tile.playerId += 1

            tile.playerId = (tile.playerId - 1) % MAX_PLAYERS + 1
            player.selectedPlayerIdx = tile.playerId - 1

            tile.visibility = {}
            tile.visibility[player.selectedPlayerIdx] = .VeryVisible
        }
        ui.pop_bounds()
    }
    
    ui.pop_layout()

    ui.pop_bounds()
    ui.pop_layout()
}

cycle_enum :: proc(value: $T, offset: int) -> T {
    return T((int(value) + len(T) + offset) % len(T))
}
import "core:strings"

textSize :: proc(text: string) -> f32 {
    buf3: [64]u8
    ctext: cstring = strings.unsafe_string_to_cstring(utils.concatenate(buf3[:], text, "\x00"))
    size := rl.MeasureText(ctext, 22)

    return f32(size)
}

enum_increment_widget :: proc(text: ^[$T]string, color: rl.Color, value: ^T) {
    size := textSize(text[value^])

    button_size: f32 = 30
    bounds_width := button_size*2 + 20 + size

    ui.add_bounds({bounds_width, button_size})
    ui.add_layout(ui.FlexBox{
        gap = 10,
        direction = .Horizontal,
        corner = {.Top, .Left}
    })

    ui.add_bounds({button_size, button_size})
    if(ui.button("-1", color)) {value^ = cycle_enum(value^, -1)}
    ui.pop_bounds()

    buf: [32]u8 
    buf2: [8]u8

    ui.add_bounds({f32(size), button_size})
    ui.text_display(text[value^], {0, 0, 0, 255})
    ui.pop_bounds()

    ui.add_bounds({button_size, button_size})
    if (ui.button("+1", color)) {value^ = cycle_enum(value^, +1)}
    ui.pop_bounds()

    ui.pop_layout()
    ui.pop_bounds()
}

increment_widget :: proc(text: string, color: rl.Color, value: ^$T) {
    buf: [32]u8 
    buf2: [8]u8
    display := utils.concatenate(buf[:], strconv.write_int(buf2[:], i64(value^), 10), " ", text)
    size := textSize(display)

    button_size: f32 = 30

    ui.add_bounds({20 + button_size*2 + size, button_size})
    ui.add_layout(ui.FlexBox{
        gap = 10,
        direction = .Horizontal,
        corner = {.Top, .Left}
    })

    ui.add_bounds({button_size, button_size})
    if(ui.button("-1", color)) {value^ -= 1}
    ui.pop_bounds()

    ui.add_bounds({size, button_size})
    ui.text_display(display, {0, 0, 0, 255})
    ui.pop_bounds()

    ui.add_bounds({button_size, button_size})
    if (ui.button("+1", color)) {value^ += 1}
    ui.pop_bounds()

    ui.pop_layout()
    ui.pop_bounds()
}

// Clean this up and add a way to change the energy per turn
edit_map_stats_ui :: proc(game: ^Game, currentPlayerIndex: u8) {
    if .Editor not_in game.non_map_modifiers {
        return
    }

    player := &game.players[currentPlayerIndex]

    ui.add_layout(ui.margin_xy(10, 95))
    ui.add_bounds()

    if player.editorStatsOpen {
        ui.add_layout(ui.FlexBox{
            gap = 10,
            corner = {.Left}
        })

        ui.add_bounds({0.6, 70})

        ui.add_layout(ui.FlexBox{
            gap = 10,
            direction = .Vertical,
            corner = {.Left, .Top}
        })

        for mode in MapSpecficModifier {
            render_modifier_toggle(&game.map_modifiers, map_modifiers, mode)
        }
        
        ui.pop_layout()
        ui.pop_bounds()    
        
        ui.pop_layout()
    }

    ui.add_layout(ui.FlexBox{
        direction = .Vertical,
        gap = 10,
    })
 
    ui.add_bounds({120, 70})
    if ui.button("settings", player.color) {
        player.editorStatsOpen = !player.editorStatsOpen
    }
    ui.pop_bounds()
    
    if player.editorStatsOpen {
        increment_widget("e/round", player.color, &game.stats.energyPerRound)
        increment_widget("size", player.color, &game.tileGrid.size)

        names := [DefaultTileStatsType]string{
            .Big = "cost preset: big",
            .Mini = "cost preset: mini"
        }
        
        enum_increment_widget(&names, player.color, &player.selectedDefaultTileStats)

        ui.add_bounds({150, 30})
        if ui.button("apply preset", player.color) {
            switch player.selectedDefaultTileStats {
                case .Mini:
                    game.map_state.tileTypeStats = defaultTileTypeStats
                case .Big:
                    game.map_state.tileTypeStats = defaultBigTileTypeStats
            }
        }
        ui.pop_bounds()    
    }
 
    ui.pop_layout()

    ui.pop_bounds()
    ui.pop_layout()
}

save_map_data :: proc(game: ^Game) -> bool {
    bytes, err := cbor.marshal_into_bytes(game.map_state, allocator=context.temp_allocator)

    if err != nil {
        log.msg("error", err)
        return false
    } 

    buf: [64]u8
    path := utils.concatenate(buf[:], "./maps/", game.mapName)

    err__ := os.write_entire_file_or_err(path, bytes)
    if err__ != nil {
        log.msg("error", err__)
        return false
    }

    return true
}

load_map_entries :: proc(game: ^Game) -> bool {
    handle, err := os.open("./maps/", os.O_RDONLY)

    if err != nil {
        log.msg("error", err)
        return false
    }

    fi, err_ := os.read_dir(handle, 16384, allocator=context.temp_allocator)
    
    if err_ != nil {
        log.msg("error", err_)
        return false
    }
    
    game.saved_map_names = make([][16]u8, len(fi))
    
    for file, i in fi {
        if file.is_dir {
            continue
        }
        
        copy_from_string(game.saved_map_names[game.saved_map_count][:], file.name)
        game.saved_map_count += 1
    }

    return true
}

load_map_data :: proc(game: ^Game, name: string) -> bool {
    currentModifiers := game.map_modifiers
    bytes, err := os.read_entire_file_from_filename_or_err(name, allocator=context.temp_allocator)

    if err != nil {
        log.msg("error", err)
        return false
    }

    err_ := cbor.unmarshal_from_bytes(bytes, &game.map_state, allocator=context.temp_allocator)

    if err_ != nil {
        log.msg("error", err_)
        return false
    }
    
    if .OverrideModifiers in game.non_map_modifiers {
        game.map_modifiers = currentModifiers     
    }

    return true
}

can_pay_active_tile_cost :: proc(game: ^Game, player: ^Player) -> bool {
    req_energy := game.tileTypeStats[player.selectedTileType].cost

    if player.tileLimits[player.selectedTileType] == 0 {
        return false
    }
    
    if u16(req_energy) > player.energy {
        return false
    }

    return true
}

pay_active_tile_cost :: proc(game: ^Game, player: ^Player) {
    req_energy := game.tileTypeStats[player.selectedTileType].cost

    player.energy -= u16(req_energy)

    if player.tileLimits[player.selectedTileType] != NA {
        player.tileLimits[player.selectedTileType] -= 1
    }
}

next_to_own_territory :: proc(game: ^Game, currentPlayerIndex: u8, halfGridPos: HalfGridPosition) -> bool {
    own_territory :: proc(game: ^Game, currentPlayerIndex: u8, tile: ^Tile) -> bool {
        player := &game.players[currentPlayerIndex]
        return tile.playerId - 1 == currentPlayerIndex && tile.type != .Blocked && tile.type != .Free
    }

    return test_adjacent_cell(game, currentPlayerIndex, halfGridPos, own_territory)
}

place_tile_editor :: proc(game: ^Game, currentPlayerIndex: u8) {
    player := &game.players[currentPlayerIndex]

    if !ui.is_left_button_pressed(player.uiFrameInfo) {
        return
    }

    within_bounds, halfgridPos := get_tile_grid_pos_safe(&game.tileGrid, player.inputState.mousePos)
    
    if !within_bounds {
        return
    }

    create_tile(game, currentPlayerIndex+1, halfgridPos)
}

can_place_tile :: proc(game: ^Game, currentPlayerIndex: u8, editor := false) -> bool {
    player := &game.players[currentPlayerIndex]

    within_bounds, halfgridPos := get_tile_grid_pos_safe(&game.tileGrid, player.inputState.mousePos)
    
    if !within_bounds {
        return false
    }
    
    if !can_pay_active_tile_cost(game, player) {
        return false
    }    

    existingTile := get_tile(&game.tileGrid, halfgridPos)

    freeTile := existingTile.type == .Free
    landTile := existingTile.type == .Land

    myTile := existingTile.playerId == currentPlayerIndex+1

    myLandTile := myTile && landTile

    _, activeTileHalfgridPos := get_active_tile(&game.tileGrid, player)

    nextToActiveTile, dir := next_to(halfgridPos, activeTileHalfgridPos)
    nextToOwnTerritory := next_to_own_territory(game, currentPlayerIndex, halfgridPos)

    switch player.selectedTileType {
    case .Blocked:
        return editor
    case .Free:
        return editor
    case .Land:
        return nextToOwnTerritory && freeTile
    case .Cannon, .Mortar, .Shield, .Defense, .Landmine, .Telescope:
        return myLandTile
    case .BlastTarget:
        return nextToActiveTile
    case .Nuke:
        return true
    case .MortarTarget:
        return true
    case .BridgeStart:
        return nextToOwnTerritory && freeTile
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

        return valid && freeTile
    }

    unreachable()
}

reveal_land :: proc(game: ^Game, playerId: u8, halfGridPos: HalfGridPosition) {
    id := playerId

    tile := get_tile(&game.tileGrid, halfGridPos)

    for dir in directions {
        for i in 1..<i16(3) {
            pos := halfGridPos + dir * i
            nextTile := get_tile(&game.tileGrid, pos)

            if nextTile.playerId != 0 {
                their_visibility := &tile.visibility[nextTile.playerId-1]

                if within_game_bounds(game, pos) && their_visibility^ < .LandVisible {
                    their_visibility^ = .LandVisible
                }
            }

            // not sure if this check is needed
            if id != 0 {
                visibility := &nextTile.visibility[id - 1]

                if within_game_bounds(game, pos) && visibility^ < .LandVisible {
                    visibility^ = .LandVisible
                }
            }
        }
    }
}

create_tile :: proc(game: ^Game, playerId: u8, halfGridPos: HalfGridPosition) {
    player := &game.players[playerId-1]
    type := player.selectedTileType
    
    activeTile, activeTileHalfgridPos := get_active_tile(&game.tileGrid, player)
    nextToActiveTile, dir := next_to(halfGridPos, activeTileHalfgridPos)

    tile := get_tile(&game.tileGrid, halfGridPos)
    if .Placeholder not_in tile_info[type].flags {
        tile ^= Tile {
            playerId = playerId,
            type = type,
            createdRound = u8(game.rounds),
            durability = game.tileTypeStats[type].durability,
            visibility = {},
            entityIds = {},
        }
    }
    tile.visibility[playerId-1] = .VeryVisible
    
    switch player.selectedTileType {
    case .Blocked:
    case .Free:
    case .Land:
        reveal_land(game, playerId, halfGridPos)
    case .Cannon, .Shield, .Defense, .Landmine:
    case .Telescope:
        for dir in directions {
            pos := halfGridPos

            for within_game_bounds(game, pos) {
                pos += dir

                get_tile(&game.tileGrid, pos).visibility[playerId-1] = .VeryVisible
            }
        }
    case .Mortar:
        tile.damage = game.tileTypeStats[.Mortar].damage
    case .BridgeStart:
        reveal_land(game, playerId, halfGridPos)
        get_tile(&game.tileGrid, halfGridPos).type = .BridgeStart
        player.selectedTileType = .BridgeEnd
    case .BridgeEnd:
        reveal_land(game, playerId, halfGridPos)
        player.selectedTileType = .BridgeStart
    case .BlastTarget:
        add_cannonball(game, activeTileHalfgridPos, halfGridPos, playerId-1, dir)

        player.activeTileId = 0
        player.editMode = .Clicking
    case .Nuke:
        add_entity(game, playerId-1, halfGridPos, SimulationEntity {
            damage = game.tileTypeStats[.BlastTarget].cost
        }, EntityType.Nuke)
        
        add_particle(game, &explosion, opts={halfGridPos})
    case .MortarTarget:
        add_entity(game, playerId - 1, halfGridPos, SimulationEntity {
            damage = activeTile.damage
        }, EntityType.MortarShot)

        add_particle(game, &explosion, opts={halfGridPos})

        player.activeTileId = 0
        player.editMode = .Clicking
    }
}

place_tile_game :: proc(game: ^Game, currentPlayerIndex: u8) {
    player := &game.players[currentPlayerIndex]

    if !ui.is_left_button_pressed(player.uiFrameInfo) {
        return
    }

    if !can_place_tile(game, currentPlayerIndex, false) {
        return
    }

    pay_active_tile_cost(game, player)

    _, halfgridPos := get_tile_grid_pos_safe(&game.tileGrid, player.inputState.mousePos)

    create_tile(game, currentPlayerIndex+1, halfgridPos)
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

        player.activeTileId = get_tile_id(halfgrid)
    }
}
