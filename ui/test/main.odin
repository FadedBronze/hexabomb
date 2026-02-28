package test_ui

import "core:fmt"
import ui "../../ui"
import rl "vendor:raylib"
import la "core:math/linalg"

main :: proc() {
    screen_size: la.Vector2f32 = {920, 800}

    rl.InitWindow(i32(screen_size.x), i32(screen_size.y), "hexabomb")
    rl.SetWindowState({.WINDOW_RESIZABLE})

    ui_buffer: ui.UI

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()

        ui.begin_ui(ui.Bounds{
            width = screen_size.x,
            height = screen_size.y,
        }, &ui_buffer)

        ui.end_ui()

        rl.EndDrawing()
    }
}
