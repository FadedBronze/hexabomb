package ui

import rl "vendor:raylib"
import rn "base:runtime"
import la "core:math/linalg"
import strings "core:strings"
import "core:math/rand"
import "../utils"

BUTTON_FONT_SIZE :: 22

@(private="file")
default_ui: ^UI

Uniquifier :: union {
    u64,
    string,
}

UI_ID :: struct {
    loc: rn.Source_Code_Location,
    uniquifier: Uniquifier,
}

FrameInfo :: struct {
    lastInputState: InputState,
    inputState: InputState,
    behaviour: FrameBehaviour,
}

MarginUnitType :: enum { 
    Pixel,
    Percent,
}

MarginRelativity :: enum {
    FromCenter,
    FromEdge,
}

MarginUnit :: struct {
    type: MarginUnitType,
    relativity: MarginRelativity,
    value: f32,
}

MarginLayout :: struct {
    top: MarginUnit,
    bottom: MarginUnit,
    left: MarginUnit,
    right: MarginUnit,
}

margin_all :: proc(
    value: f32, 
    type := MarginUnitType.Pixel, 
    relativity := MarginRelativity.FromEdge
) -> MarginLayout {
    v := MarginUnit{
        type,
        relativity,
        value,
    }
    return MarginLayout {
        top = v,
        bottom = v,
        left = v,
        right = v,
    }
}

margin_xy :: proc(
    x: f32, 
    y: f32, 
    type := MarginUnitType.Pixel, 
    relativity := MarginRelativity.FromEdge
) -> MarginLayout {
    x_v := MarginUnit{
        type = type,
        relativity = relativity,
        value = x,
    }
    y_v := MarginUnit{
        type = type,
        relativity = relativity,
        value = y,
    }
    return MarginLayout {
        top=y_v,
        bottom=y_v,
        left=x_v,
        right=x_v,
    }
}

margin_tblr :: proc(t, b, l, r: f32, type := MarginUnitType.Pixel, relativity := MarginRelativity.FromEdge) -> MarginLayout {
    t_v := MarginUnit{
        type = type,
        relativity = relativity,
        value = t,
    }
    b_v := MarginUnit{
        type = type,
        relativity = relativity,
        value = b,
    }
    l_v := MarginUnit{
        type = type,
        relativity = relativity,
        value = l,
    }
    r_v := MarginUnit{
        type = type,
        relativity = relativity,
        value = r,
    }
    return MarginLayout {
        top=t_v,
        bottom=b_v,
        left=l_v,
        right=r_v,
    }
}

margin :: proc {
    margin_all,
    margin_xy,
    margin_tblr,
}

Layout :: union {
    MarginLayout,
    FlexBox,
}

FlexSpacing :: enum {
    Spread,
    Center,
    Left,
    Right,
}

FlexCorner :: enum {
    TopLeft,
    TopRight,
    BottomLeft,
    BottomRight,
}

FlexDirection :: enum {
    Horizontal,
    Vertical,
}

FlexBox :: struct {
    direction: FlexDirection,
    corner: FlexCorner,
    gap: f32,
}

MAX_LAYOUT_STACK :: 16

UICache :: struct {
    offset: la.Vector2f32,
    maxSizes: la.Vector2f32,
}

Bounds :: struct {
    using rect: rl.Rectangle
}

UI :: struct {
    activeId: UI_ID,
    buttons_length: u16,
    button_offset: u32,
    screenSize: [2]f32,

    boundsStack: [MAX_LAYOUT_STACK]Bounds,
    layoutStack: [MAX_LAYOUT_STACK]Layout,
    stackSize: u16,

    cache: UICache,
    using frameInfo: ^FrameInfo,
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

FrameBehaviour :: bit_set [enum {
    Draw,
    Update,
}]

init :: proc(ui_ptr: ^UI) {
    assert(ui_ptr != nil)
    default_ui = ui_ptr
}

within_bounds :: proc(rect: rl.Rectangle, pos: la.Vector2f32) -> bool {
    return pos.x < rect.x + rect.width && pos.x > rect.x && pos.y < rect.y + rect.height && pos.y > rect.y
}

begin_ui :: proc(bounds: Bounds, ui := default_ui) {
    ui.cache = UICache{}
    assert(ui.stackSize == 0)
    ui.boundsStack[ui.stackSize] = bounds
    ui.stackSize += 1
}

end_ui :: proc(ui := default_ui) {
    ui.stackSize -= 1
    assert(ui.stackSize == 0)
}

add_bounds :: proc(bounds: la.Vector2f32 = {0, 0}, ui := default_ui) {
    layout := ui.layoutStack[ui.stackSize-1]
    layout_bounds := ui.boundsStack[ui.stackSize-1]

    b := Bounds {
        width = bounds.x,
        height = bounds.y,
    }
    
    switch v in layout {
    case nil:
        // Cannot add a bounds onto a bounds
        fmt.println(ui.layoutStack[0:ui.stackSize], ui.stackSize)
        assert(false)
    case FlexBox:
        switch v.corner {
        case .TopLeft:
            switch v.direction {
            case .Horizontal:
                ui.cache.maxSizes.y = max(ui.cache.maxSizes.y, b.height)

                if ui.cache.offset.x + b.width > layout_bounds.width {
                    ui.cache.offset.y += ui.cache.maxSizes.y + v.gap
                    ui.cache.offset.x = 0
                    ui.cache.maxSizes.y = 0
                }

                ui.boundsStack[ui.stackSize] = Bounds {
                    width = b.width,
                    height = b.height,
                    x = ui.cache.offset.x + layout_bounds.x,
                    y = ui.cache.offset.y + layout_bounds.y,
                }
                ui.stackSize += 1

                ui.cache.offset.x += b.width + v.gap
            case .Vertical:
                ui.cache.maxSizes.x = max(ui.cache.maxSizes.x, b.width)

                if ui.cache.offset.y + b.height > layout_bounds.height {
                    ui.cache.offset.x += ui.cache.maxSizes.x + v.gap
                    ui.cache.offset.y = 0
                    ui.cache.maxSizes.x = 0
                }

                ui.boundsStack[ui.stackSize] = Bounds {
                    width = b.width,
                    height = b.height,
                    x = ui.cache.offset.x + layout_bounds.x,
                    y = ui.cache.offset.y + layout_bounds.y,
                }

                ui.stackSize += 1
                ui.cache.offset.y += b.height + v.gap
            }
        case .TopRight:
            switch v.direction {
            case .Horizontal:
                unimplemented()
            case .Vertical:
                ui.cache.maxSizes.x = max(ui.cache.maxSizes.x, b.width)

                if ui.cache.offset.y + b.height > layout_bounds.height {
                    ui.cache.offset.x += ui.cache.maxSizes.x + v.gap
                    ui.cache.offset.y = 0
                    ui.cache.maxSizes.x = 0
                }

                ui.boundsStack[ui.stackSize] = Bounds {
                    width = b.width,
                    height = b.height,
                    x = layout_bounds.width + layout_bounds.x - ui.cache.offset.x - b.width,
                    y = ui.cache.offset.y + layout_bounds.y,
                }

                ui.stackSize += 1
                ui.cache.offset.y += b.height + v.gap
            }
        case .BottomLeft:
            switch v.direction {
            case .Horizontal:
                ui.cache.maxSizes.y = max(ui.cache.maxSizes.y, b.height)

                if ui.cache.offset.x + b.width > layout_bounds.width {
                    ui.cache.offset.y += ui.cache.maxSizes.y + v.gap
                    ui.cache.offset.x = 0
                    ui.cache.maxSizes.y = 0
                }

                ui.boundsStack[ui.stackSize] = Bounds {
                    width = b.width,
                    height = b.height,
                    x = ui.cache.offset.x + layout_bounds.x,
                    y = layout_bounds.height + layout_bounds.y - ui.cache.offset.y - b.height,
                }
                ui.stackSize += 1

                ui.cache.offset.x += b.width + v.gap
            case .Vertical:
                unimplemented()
            }
        case .BottomRight:
            switch v.direction {
            case .Horizontal:
                ui.cache.maxSizes.y = max(ui.cache.maxSizes.y, b.height)

                if ui.cache.offset.x + b.width > layout_bounds.width {
                    ui.cache.offset.y += ui.cache.maxSizes.y + v.gap
                    ui.cache.offset.x = 0
                    ui.cache.maxSizes.y = 0
                }

                ui.boundsStack[ui.stackSize] = Bounds {
                    width = b.width,
                    height = b.height,
                    x = layout_bounds.width + layout_bounds.x - ui.cache.offset.x - b.width,
                    y = layout_bounds.height + layout_bounds.y - ui.cache.offset.y - b.height,
                }
                ui.stackSize += 1

                ui.cache.offset.x += b.width + v.gap
            case .Vertical:
                unimplemented()
            }
        }
    case MarginLayout:
        // Case 1
        case1 := Bounds {
            x = v.left.value + layout_bounds.x,
            y = v.top.value + layout_bounds.y,
            width = layout_bounds.width - (v.right.value+v.left.value),
            height = layout_bounds.height - (v.top.value+v.bottom.value)
        }

        // Case 2
        case2 := Bounds {
            x = layout_bounds.x + layout_bounds.width / 2 - v.left.value,
            y = layout_bounds.y + layout_bounds.height / 2 - v.top.value,
            width = v.right.value+v.left.value,
            height = v.top.value+v.bottom.value
        }

        // Subcases
        all := Bounds {
            x = v.left.relativity == .FromEdge ? case1.x : case2.x,
            y = v.top.relativity == .FromEdge ? case1.y : case2.y,
        }

        switch v.right.relativity {
        case .FromCenter:
            switch v.left.relativity {
            case .FromCenter:
                all.width = case2.width
            case .FromEdge:
                all.width = layout_bounds.width / 2 - v.right.value + v.left.value
            }
        case .FromEdge:
            switch v.left.relativity {
            case .FromCenter:
                all.width = layout_bounds.width / 2 + v.right.value - v.left.value
            case .FromEdge:
                all.width = case1.width
            }
        }
        
        switch v.top.relativity {
        case .FromCenter:
            switch v.bottom.relativity {
            case .FromCenter:
                all.height = case2.height
            case .FromEdge:
                all.height = layout_bounds.height / 2 - v.top.value + v.bottom.value
            }
        case .FromEdge:
            switch v.bottom.relativity {
            case .FromCenter:
                all.height = layout_bounds.height / 2 + v.top.value - v.bottom.value
            case .FromEdge:
                all.height = case1.height
            }
        }

        ui.boundsStack[ui.stackSize] = all
        ui.stackSize += 1
    }
}

import "core:fmt"

add_layout :: proc(layout: Layout, ui := default_ui) {
    // should have more bounds then layouts
    assert(ui.layoutStack[ui.stackSize-1] == nil)
    
    bounds := ui.boundsStack[ui.stackSize-1]
    ui.layoutStack[ui.stackSize-1] = layout

    ui.cache.maxSizes = 0
    ui.cache.offset = 0
}

pop_bounds :: proc(ui := default_ui) {
    // TODO -> checking
    ui.stackSize -= 1
}

pop_layout :: proc(ui := default_ui) {
    // TODO -> checking
    ui.layoutStack[ui.stackSize-1] = nil
}

is_left_button_pressed :: proc(frameInfo: ^FrameInfo) -> bool {
    return frameInfo.inputState.leftButton == .Down && frameInfo.lastInputState.leftButton == .Up
}

button :: proc(
    text: string, 
    color: rl.Color, 
    loc := #caller_location, 
    id: Uniquifier = 0, 
    ui := default_ui
) -> bool {
    return within_button(
        text, 
        color, 
        id = id, 
        loc = loc, 
        ui = ui
    ) && is_left_button_pressed(ui.frameInfo)
}

get_bounds :: proc(ui := default_ui) -> Bounds {
    // TODO -> checking
    return ui.boundsStack[ui.stackSize-1]
}

within_button :: proc(
    text: string, 
    color: rl.Color, 
    loc := #caller_location, 
    id: Uniquifier = 0, 
    ui := default_ui
) -> bool {
    id := UI_ID {
        uniquifier = id,
        loc = loc,
    }

    bounds := get_bounds(ui)

    col := color / rl.Color { 2, 2, 2, 1 } + rl.Color{255, 255, 255, 0} / 2
    col2 := color / rl.Color { 3, 3, 3, 1 } + rl.Color{255, 255, 255, 0} / 3 * 2

    if .Draw in ui.frameInfo.behaviour {
        rl.DrawRectangleRec(bounds, col)
    }
    within_button := within_bounds(bounds, ui.frameInfo.inputState.mousePos)
    mouse_down := ui.frameInfo.inputState.leftButton == .Down

    if within_button {
        ui.activeId = id

        if mouse_down {
            if .Draw in ui.frameInfo.behaviour {
                rl.DrawRectangleRec(bounds, col2)
            }
        }
    }

    if !within_button && id == ui.activeId {
        ui.activeId = empty_id()
    }

    pressed := false

    if id == ui.activeId {
        if .Draw in ui.frameInfo.behaviour {
            rl.DrawRectangleLines(i32(bounds.x), i32(bounds.y), i32(bounds.width), i32(bounds.height), rl.BLACK)
        }
        pressed = is_left_button_pressed(ui.frameInfo)
    }

    buf: [64]u8
    str := strings.unsafe_string_to_cstring(utils.concatenate(buf[:], text, "\x00"))

    text_width := rl.MeasureText(str, BUTTON_FONT_SIZE)

    if .Draw in ui.frameInfo.behaviour {
        rl.DrawText(str, i32(bounds.x + bounds.width/2) - i32(text_width)/2, i32(bounds.y + bounds.height/2) - BUTTON_FONT_SIZE/2, BUTTON_FONT_SIZE, rl.BLACK)
    }

    return within_button && .Update in ui.frameInfo.behaviour
}

text_display :: proc(
    text: string, 
    color: rl.Color, 
    text_size: i32 = BUTTON_FONT_SIZE, 
    id := #caller_location, 
    ui := default_ui
) {
    rectangle := get_bounds()

    if .Draw not_in ui.frameInfo.behaviour {
        return
    }

    str := strings.unsafe_string_to_cstring(strings.concatenate({text, "\x00"}, allocator=context.temp_allocator))
    text_width := rl.MeasureText(str, text_size)

    rl.DrawText(str, i32(rectangle.x + rectangle.width/2) - i32(text_width)/2, i32(rectangle.y + rectangle.height/2) - BUTTON_FONT_SIZE/2, text_size, color)
}

empty_id :: proc() -> UI_ID {
    return UI_ID {}
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

active_id :: proc(ui := default_ui) -> ^UI_ID {
    return &ui.activeId
}

flat_color :: proc(color: rl.Color, ui := default_ui) {
    bounds := get_bounds(ui)
    rl.DrawRectangleRec(bounds.rect, color)
}

toggle :: proc(
    on_color: rl.Color, 
    off_color: rl.Color, 

    toggled: bool,

    loc := #caller_location, 
    id: Uniquifier = 0, 
    ui := default_ui
) -> bool {
    bounds := get_bounds()

    col := on_color / rl.Color { 2, 2, 2, 1 } + rl.Color{255, 255, 255, 0} / 2
    col2 := off_color / rl.Color { 2, 2, 2, 1 } + rl.Color{255, 255, 255, 0} / 2

    if toggled {
        rl.DrawRectangleRec(bounds.rect, col)
    } else {
        rl.DrawRectangleRec(bounds.rect, col2)
    }

    within := within_bounds(bounds, ui.inputState.mousePos)
 
    if within {
        if .Draw in ui.frameInfo.behaviour {
            rl.DrawRectangleLines(i32(bounds.x), i32(bounds.y), i32(bounds.width), i32(bounds.height), rl.BLACK)
        }
    }
    
    return within && is_left_button_pressed(ui.frameInfo) && .Update in ui.frameInfo.behaviour
}
