package ui

import rl "vendor:raylib"
import rn "base:runtime"
import la "core:math/linalg"
import strings "core:strings"
import "core:math/rand"

BUTTON_FONT_SIZE :: 22

UI :: struct {
    nextFreeId: u32,
    activeId: rn.Source_Code_Location,
    buttons_length: u16,
    button_offset: u32,
    active_layout: Layout,
}

MouseState :: enum {
    Up,
    Down,
}

InputState :: struct {
    mousePos: la.Vector2f32,
    screenSize: la.Vector2f32,
    leftButton: MouseState,
}

FrameInfo :: struct {
    lastInputState: InputState,
    inputState: InputState,
    virtual: bool,
}

RowDirection :: enum {
    Up,
    Down,
    Left,
    Right,
}

EmptyLayout :: struct {}

Layout :: union {
    EmptyLayout,
    RowLayout,
}

RowLayout :: struct {
    direction: RowDirection,
    x_offset: f32,
    y_offset: f32,
    gap: f32,
    bounds: [2]f32,
}

row_layout :: proc(ui: ^UI, direction: RowDirection, offset: la.Vector2f32, gap: f32) {
    ui.active_layout = RowLayout{
        direction = direction,
        x_offset = offset.x,
        y_offset = offset.y,
        gap = gap,
    }
}

row_layout_end :: proc(ui: ^UI) {
    ui.active_layout = EmptyLayout{}
}

within_rectangle :: proc(rect: rl.Rectangle, pos: la.Vector2f32) -> bool {
    return pos.x < rect.x + rect.width && pos.x > rect.x && pos.y < rect.y + rect.height && pos.y > rect.y
}

update_layout :: proc(ui: ^UI, rectangle: ^rl.Rectangle) {
    #partial switch &layout in &ui.active_layout {
    case RowLayout: 
        rectangle.x = layout.x_offset
        rectangle.y = layout.y_offset

        if layout.direction == .Left {
            rectangle.x -= rectangle.width
        } else if layout.direction == .Up {
            rectangle.y -= rectangle.height
        }

        switch layout.direction {
        case .Up:
            layout.y_offset += rectangle.height + layout.gap
        case .Down:
            layout.y_offset -= rectangle.height + layout.gap
        case .Left:
            layout.x_offset -= rectangle.width + layout.gap
        case .Right:
            layout.x_offset += rectangle.width + layout.gap
        }
    }
}

is_left_button_pressed :: proc(uiFrameInfo: ^FrameInfo) -> bool {
    return uiFrameInfo.inputState.leftButton == .Down && uiFrameInfo.lastInputState.leftButton == .Up
}

button :: proc(ui: ^UI, uiFrameInfo: ^FrameInfo, rectangle: rl.Rectangle, text: string, color: rl.Color, id := #caller_location) -> bool {
    return within_button(ui, uiFrameInfo, rectangle, text, color, id) && is_left_button_pressed(uiFrameInfo)
}

within_button :: proc(ui: ^UI, uiFrameInfo: ^FrameInfo, rectangle: rl.Rectangle, text: string, color: rl.Color, id := #caller_location) -> bool {
    rectangle := rectangle

    update_layout(ui, &rectangle)

    col := color / rl.Color { 2, 2, 2, 1 } + rl.Color{255, 255, 255, 0} / 2
    col2 := color / rl.Color { 3, 3, 3, 1 } + rl.Color{255, 255, 255, 0} / 3 * 2

    if !uiFrameInfo.virtual {
        rl.DrawRectangleRec(rectangle, col)
    }
    within_button := within_rectangle(rectangle, uiFrameInfo.inputState.mousePos)
    mouse_down := uiFrameInfo.inputState.leftButton == .Down

    if within_button {
        ui.activeId = id

        if mouse_down {
            if !uiFrameInfo.virtual {
                rl.DrawRectangleRec(rectangle, col2)
            }
        }
    }

    if !within_button && id == ui.activeId {
        ui.activeId = rn.Source_Code_Location{}
    }

    pressed := false

    if id == ui.activeId {
        if !uiFrameInfo.virtual {
            rl.DrawRectangleLines(i32(rectangle.x), i32(rectangle.y), i32(rectangle.width), i32(rectangle.height), rl.BLACK)
        }
        pressed = is_left_button_pressed(uiFrameInfo)
    }

    str := strings.unsafe_string_to_cstring(strings.concatenate({text, "\x00"}))

    text_width := rl.MeasureText(str, BUTTON_FONT_SIZE)

    if !uiFrameInfo.virtual {
        rl.DrawText(str, i32(rectangle.x + rectangle.width/2) - i32(text_width)/2, i32(rectangle.y + rectangle.height/2) - BUTTON_FONT_SIZE/2, BUTTON_FONT_SIZE, rl.BLACK)
    }

    return within_button
}

text_display :: proc(ui: ^UI, uiFrameInfo: ^FrameInfo, rectangle: rl.Rectangle, text: string, color: rl.Color, text_size: i32 = BUTTON_FONT_SIZE, id := #caller_location) {
    rectangle := rectangle
    update_layout(ui, &rectangle)

    if uiFrameInfo.virtual {
        return
    }

    str := strings.unsafe_string_to_cstring(strings.concatenate({text, "\x00"}))
    text_width := rl.MeasureText(str, text_size)

    rl.DrawText(str, i32(rectangle.x + rectangle.width/2) - i32(text_width)/2, i32(rectangle.y + rectangle.height/2) - BUTTON_FONT_SIZE/2, text_size, color)
}

empty_id :: proc() -> rn.Source_Code_Location {
    return rn.Source_Code_Location{}
}

get_button_state :: proc() -> MouseState {
    if rl.IsMouseButtonDown(.LEFT) {
        return .Down
    }

    if rl.IsMouseButtonUp(.LEFT) {
        return .Up
    }

    unreachable()
}

get_input_state :: proc() -> InputState {
    screenSize := la.Vector2f32{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

    return InputState {
        mousePos = rl.GetMousePosition(),
        leftButton = get_button_state(),
        screenSize = screenSize,
    }
}

generate_random_input :: proc(screenSize: [2]f32) -> InputState {
    return InputState {
        mousePos = {
            screenSize.x * rand.float32(),
            screenSize.y * rand.float32(),
        },
        screenSize = screenSize,
        leftButton = MouseState(rand.float32() * f32(max(MouseState))+1)
    }
}
