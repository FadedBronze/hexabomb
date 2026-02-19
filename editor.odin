package main

import "core:encoding/cbor"
import "core:os"

import "log"
import "ui"
import "utils"

active_tile_editor_ui :: proc(game: ^Game, currentPlayerIndex: u8) {
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

place_tile_editor :: proc(game: ^Game, currentPlayerIndex: u8) {
    player := &game.players[currentPlayerIndex]

    if !ui.is_left_button_pressed(player.uiFrameInfo) {
        return
    }

    within_bounds, halfgridPos := get_tile_grid_pos_safe(&game.tileGrid, player.inputState.mousePos)
    
    if !within_bounds {
        return
    }

    tile := get_tile(&game.tileGrid, halfgridPos)
    tile^ = create_tile(game, currentPlayerIndex+1, halfgridPos, player.selectedTileType)

    if tile.type != .Blocked || tile.type != .Free {
        tile.playerId = player.selectedPlayerIdx + 1
    }
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

    return true
}
