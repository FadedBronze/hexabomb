package ui
import rl "vendor:raylib"
import rn "base:runtime"
import la "core:math/linalg"
import strings "core:strings"
import "../utils"
import "core:fmt"
import box "../containers"

BUTTON_FONT_SIZE :: 22
@(private="file")
ui_handle: ^UI

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

FlexCorner :: bit_set[enum {
    Left,
    Top,
}]

FlexDirection :: enum {
    Horizontal,
    Vertical,
}

FlexSpacing :: enum {
    Linear,
    Centered,
    Spaced,
}

FlexBox :: struct {
    //properties
    id: UI_ID,
    direction: FlexDirection,
    corner: FlexCorner,
    spacing: FlexSpacing,
    gap: f32,
    //state
    offset: la.Vector2f32,
    maxSizes: la.Vector2f32,
}

MAX_LAYOUT_STACK :: 16

Trigger :: struct {
    type: TriggerType,
    bounds: Bounds,
    depth: u16,
    // At the end of the frame, if it is the lowest depth trigger,
    // it will be confirmed for the next frame.
    confirmed: bool,
}

UICache :: struct {
    prevFlexOffset: box.SmallMap(64, UI_ID, la.Vector2f32),
    prevTriggers: box.SmallMap(64, UI_ID, Trigger),
}

Bounds :: struct {
    using rect: rl.Rectangle
}

InputMode :: enum {
    Keyboard,
    Mouse
}

UI :: struct {
    activeId: UI_ID,
    selectedBounds: Bounds,
    inputMode: InputMode,
    cursorLocation: la.Vector2f32,

    boundsStack: [MAX_LAYOUT_STACK]Bounds,
    layoutStack: [MAX_LAYOUT_STACK]Layout,
    stackSize: u16,

    cache: UICache,
    using frameContext: ^FrameInfo,
}

InputKey :: enum {
    leftMouseButton,
    W,
    A,
    S,
    D,
    Q,
    E,
    Enter,
    Backspace,
}

InputState :: struct {
    mousePos: la.Vector2f32,
    screenSize: la.Vector2f32,
    down: bit_set[InputKey]
}

FrameBehaviour :: bit_set [enum {
    Draw,
    Update,
}]

within_bounds :: proc(rect: rl.Rectangle, pos: la.Vector2f32) -> bool {
    return pos.x < rect.x + rect.width && pos.x > rect.x && pos.y < rect.y + rect.height && pos.y > rect.y
}

centerpoint :: proc(bounds: Bounds) -> la.Vector2f32 {
    return {bounds.x + bounds.width/2, bounds.y + bounds.height/2}
}

begin_ui :: proc(ui_ptr: ^UI, bounds: Bounds) {
    assert(ui_ptr != nil)
    ui_handle = ui_ptr
    assert(ui_handle.stackSize == 0)
    ui_handle.boundsStack[ui_handle.stackSize] = bounds
    ui_handle.stackSize += 1
}

mouse_pos_unchanged :: proc(frameContext: ^FrameInfo) -> bool {
    return frameContext.lastInputState.mousePos == frameContext.inputState.mousePos
}

any_button_pressed :: proc(frameContext: ^FrameInfo, buttons: ..InputKey) -> bool {
    for button in buttons {
        if is_button_pressed(frameContext, button) {
            return true
        }
    }
    return false
}

any_button_held :: proc(frameContext: ^FrameInfo, buttons: ..InputKey) -> bool {
    for button in buttons {
        if is_button_held(frameContext, button) {
            return true
        }
    }
    return false
}

end_ui :: proc(ui := ui_handle) {
    if !mouse_pos_unchanged(ui.frameContext) {
        ui.inputMode = .Mouse
    } 
    if any_button_pressed(ui.frameContext, .W, .A, .S, .D) {
        ui.inputMode = .Keyboard
    }
    smi_ := box.sm_iterator(&ui_handle.cache.prevTriggers)
    for id, trigger in box.sm_iterate(&smi_) {
        if trigger.confirmed {
            box.sm_remove(&smi_)
            continue
        }
    }
    switch ui.inputMode {
    case .Keyboard:
        best_trigger: Trigger
        best_trigger.bounds.x = 10000
        best_trigger.bounds.y = 10000
        best_trigger_id: UI_ID
        smi := box.sm_iterator(&ui_handle.cache.prevTriggers)
        for id, trigger in box.sm_iterate(&smi) {
            trigger_center := centerpoint(trigger.bounds)
            delta := la.vector_length(trigger_center - ui.cursorLocation)
            best_center := centerpoint(best_trigger.bounds)
            bestDelta := la.vector_length(best_center - ui.cursorLocation)
            if delta <= bestDelta && delta > 5 { 
                if is_button_pressed(ui_handle.frameContext, .W) && trigger_center.y < ui.cursorLocation.y {
                    best_trigger = trigger
                    best_trigger_id = id
                } else if is_button_pressed(ui_handle.frameContext, .S) && trigger_center.y > ui.cursorLocation.y {
                    best_trigger = trigger
                    best_trigger_id = id
                } else if is_button_pressed(ui_handle.frameContext, .A) && trigger_center.x < ui.cursorLocation.x {
                    best_trigger = trigger
                    best_trigger_id = id
                } else if is_button_pressed(ui_handle.frameContext, .D) && trigger_center.x > ui.cursorLocation.x {
                    best_trigger = trigger
                    best_trigger_id = id
                }
            }
        }
        if best_trigger_id != empty_id() {
            ui.cursorLocation = centerpoint(best_trigger.bounds)
        }
        fmt.println(ui.cursorLocation)
    case .Mouse:
        ui.cursorLocation = ui.inputState.mousePos
    }
    active_id := empty_id()
    active_trigger := Trigger{}
    smi := box.sm_iterator(&ui.cache.prevTriggers)
    for k, v in box.sm_iterate_ptr(&smi) {
        if within_bounds(v.bounds, ui.cursorLocation) {
            active_trigger.type = any_button_held(ui, .leftMouseButton, .Enter) ? .Down : .Up
            if any_button_pressed(ui, .leftMouseButton, .Enter) {
                active_trigger.type = .Clicked
            }
            if v.depth > active_trigger.depth {
                active_trigger.depth = v.depth
                active_trigger.bounds = v.bounds
                active_trigger.confirmed = true
                active_id = k
            }
        }
        v.confirmed = true
        v.type = .NotActive
    }
    if active_id != empty_id() {
        box.sm_set(&ui.cache.prevTriggers, active_id, active_trigger)
        ui.activeId = active_id
    } else {
        ui.activeId = empty_id()
    }
    ui.stackSize -= 1
    assert(ui.stackSize == 0)
}

add_bounds :: proc(bounds: la.Vector2f32 = {1, 1}, ui := ui_handle) {
    layout := &ui.layoutStack[ui.stackSize-1]
    layout_bounds := ui.boundsStack[ui.stackSize-1]
    b := Bounds {
        width = (-1 <= bounds.x && bounds.x <= 1) ? bounds.x * layout_bounds.width : bounds.x,
        height = (-1 <= bounds.y && bounds.y <= 1) ? bounds.y * layout_bounds.height : bounds.y,
    }
    switch &v in layout {
    case nil:
        // Cannot add a bounds onto a bounds
        fmt.println(ui.layoutStack[0:ui.stackSize], ui.stackSize)
        assert(false)
    case FlexBox:
        assert(b.width != 0 && b.height != 0)
        x_off := .Left not_in v.corner ?\
            layout_bounds.width + layout_bounds.x - b.width :\ 
            layout_bounds.x
        y_off := .Top not_in v.corner ?\ 
            layout_bounds.height + layout_bounds.y - b.height :\ 
            layout_bounds.y
        switch v.spacing {
        case .Linear:
            //default
        case .Centered:
            prevFlexOffset := box.sm_get_ptr(&ui_handle.cache.prevFlexOffset, v.id)

            switch v.direction {
            case .Horizontal:
                x_off = layout_bounds.x + layout_bounds.width / 2 - prevFlexOffset.x / 2
            case .Vertical:
                y_off = layout_bounds.y + layout_bounds.height / 2 - prevFlexOffset.y / 2
            }
        case .Spaced:
            unimplemented()
        }
        switch v.direction {
        case .Horizontal:
            v.maxSizes.y = max(v.maxSizes.y, b.height)
            if v.offset.x + b.width > layout_bounds.width {
                v.offset.y += v.maxSizes.y + v.gap
                v.offset.x = 0
                v.maxSizes.y = 0
            }
            ui.boundsStack[ui.stackSize] = Bounds {
                width = b.width,
                height = b.height,
                x = x_off + (.Left not_in v.corner ? -v.offset.x : v.offset.x),
                y = y_off + (.Top not_in v.corner ? -v.offset.y : v.offset.y),
            }
            ui.stackSize += 1
            v.offset.x += b.width + v.gap
        case .Vertical:
            v.maxSizes.x = max(v.maxSizes.x, b.width)

            if v.offset.y + b.height > layout_bounds.height {
                v.offset.x += v.maxSizes.x + v.gap
                v.offset.y = 0
                v.maxSizes.x = 0
            }
            ui.boundsStack[ui.stackSize] = Bounds {
                width = b.width,
                height = b.height,
                x = x_off + (.Left not_in v.corner ? -v.offset.x : v.offset.x),
                y = y_off + (.Top not_in v.corner ? -v.offset.y : v.offset.y),
            }
            ui.stackSize += 1
            v.offset.y += b.height + v.gap
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

add_layout :: proc(layout: Layout, ui := ui_handle, loc := #caller_location, id: Uniquifier = 0) {
    // should have more bounds then layouts
    assert(ui.layoutStack[ui.stackSize-1] == nil)
    bounds := ui.boundsStack[ui.stackSize-1]
    ui.layoutStack[ui.stackSize-1] = layout
    switch &v in &ui.layoutStack[ui.stackSize-1] {
    case FlexBox:
        v.id = UI_ID{ uniquifier = id, loc = loc }
    case MarginLayout:
    }
}

pop_bounds :: proc(ui := ui_handle) {
    // TODO -> checking
    ui.stackSize -= 1
}

pop_layout :: proc(ui := ui_handle) {
    switch &v in &ui.layoutStack[ui.stackSize-1] {
    case FlexBox:
        if v.direction == .Horizontal {
            v.offset.y += v.maxSizes.y
            v.offset.x -= v.gap
        } else {
            v.offset.x += v.maxSizes.x
            v.offset.y -= v.gap
        }

        box.sm_set(&ui_handle.cache.prevFlexOffset, v.id, v.offset)
    case MarginLayout:
    }
    // TODO -> checking
    ui.layoutStack[ui.stackSize-1] = nil
}

is_button_held :: proc(frameContext: ^FrameInfo, key: InputKey) -> bool {
    return key in frameContext.inputState.down
}

is_button_pressed :: proc(frameContext: ^FrameInfo, key: InputKey) -> bool {
    if .Update not_in frameContext.behaviour {
        return false
    }
    return key in frameContext.inputState.down && key not_in frameContext.lastInputState.down
}

TriggerType :: enum {
    NotActive,
    Up,
    Down,
    Clicked,
}

get_bounds :: proc(ui: ^UI) -> Bounds {
    return ui.boundsStack[ui.stackSize-1]
}

trigger :: proc(
    loc := #caller_location, id: Uniquifier = 0, ui := ui_handle
) -> (TriggerType, Bounds) {
    return trigger_(ui, loc, id)
}

trigger_ :: proc(
    ui: ^UI,
    loc: rn.Source_Code_Location, 
    id: Uniquifier, 
) -> (TriggerType, Bounds) {
    id := UI_ID { uniquifier = id, loc = loc }
    prevTrigger := box.sm_get(&ui.cache.prevTriggers, id)
    bounds := ui.boundsStack[ui.stackSize-1]
    box.sm_set(&ui.cache.prevTriggers, id, Trigger {
        type = .NotActive,
        depth = ui.stackSize,
        bounds = bounds,
        confirmed = false,
    })
    return prevTrigger.type, prevTrigger.bounds
}

button :: proc(
    text: string, color: rl.Color, size := BUTTON_FONT_SIZE,
    loc := #caller_location, id: Uniquifier = 0, ui := ui_handle
) -> bool {
    return button_base(text, color, size, loc, id, ui) == .Clicked
}

held_button :: proc(
    text: string, color: rl.Color, size := BUTTON_FONT_SIZE,
    loc := #caller_location, id: Uniquifier = 0, ui := ui_handle
) -> bool {
    return button_base(text, color, size, loc, id, ui) == .Down
}

fill_rect :: proc(ui: ^UI, colour: rl.Color, bounds: Bounds) {
    if .Draw not_in ui.behaviour { return }
    rl.DrawRectangleRec(bounds.rect, colour)
}

outline_rect :: proc(ui: ^UI, colour: rl.Color, bounds: Bounds) {
    if .Draw not_in ui.behaviour { return }
    rl.DrawRectangleLines(i32(bounds.x), i32(bounds.y), i32(bounds.width), i32(bounds.height), colour)
}

button_base :: proc( 
    text: string, color: rl.Color, size := BUTTON_FONT_SIZE,
    loc := #caller_location, id: Uniquifier = 0, ui := ui_handle
) -> TriggerType {
    trigger, bounds := trigger_(ui, loc, id)
    fill_rect(ui, utils.blend_two_colors(color, rl.WHITE, 0.50), bounds)
    if trigger == .Down { fill_rect(ui, utils.blend_two_colors(color, rl.WHITE, 0.66), bounds) }
    if trigger != .NotActive { outline_rect(ui, rl.BLACK, bounds) }
    if .Draw in ui.frameContext.behaviour { draw_text(ui, text, rl.BLACK, bounds, size) }
    return trigger
}

draw_text :: proc(
    ui: ^UI, text: string, colour: rl.Color, 
    bounds: Bounds, size: int
) {
    buf: [64]u8
    str := strings.unsafe_string_to_cstring(utils.concatenate(buf[:], text, "\x00"))
    text_width := rl.MeasureText(str, i32(size))
    rl.DrawText(
        str, 
        i32(bounds.x + bounds.width/2) - i32(text_width)/2, 
        i32(bounds.y + bounds.height/2) - i32(size)/2, 
        i32(size), 
        colour,
    )
}

text_display :: proc(
    text: string, colour: rl.Color, 
    size: int = BUTTON_FONT_SIZE, id := #caller_location, ui := ui_handle
) {
    rectangle := get_bounds(ui)
    draw_text(ui, text, colour, rectangle, size)
}

empty_id :: proc() -> UI_ID { return UI_ID {} }

get_button_state :: proc() -> bit_set[InputKey] {
    res: bit_set[InputKey] = {}
    if rl.IsMouseButtonDown(.LEFT) { res += { .leftMouseButton } }
    if rl.IsKeyDown(.W) { res += { .W } }
    if rl.IsKeyDown(.A) { res += { .A } }
    if rl.IsKeyDown(.S) { res += { .S } }
    if rl.IsKeyDown(.D) { res += { .D } }
    if rl.IsKeyDown(.Q) { res += { .Q } }
    if rl.IsKeyDown(.E) { res += { .E } }
    if rl.IsKeyDown(.ENTER) { res += { .Enter } }
    if rl.IsKeyDown(.BACKSPACE) { res += { .Backspace } }
    return res
}

get_input_state :: proc() -> InputState {
    screenSize := la.Vector2f32{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
    return InputState {
        mousePos = rl.GetMousePosition(),
        down = get_button_state(),
        screenSize = screenSize,
    }
}

active_id :: proc(ui := ui_handle) -> ^UI_ID {
    return &ui.activeId
}

outline :: proc(color: rl.Color, ui := ui_handle) {
    bounds := get_bounds(ui)
    if .Draw in ui.behaviour {
        rl.DrawRectangleLines(i32(bounds.x), i32(bounds.y), i32(bounds.width), i32(bounds.height), rl.BLACK)
    }
}

flat_color :: proc(color: rl.Color, ui := ui_handle) {
    bounds := get_bounds(ui)
    if .Draw in ui.behaviour {
        rl.DrawRectangleRec(bounds.rect, color)
    }
}

toggle :: proc(
    on_color: rl.Color, 
    off_color: rl.Color, 
    toggled: bool,
    loc := #caller_location, 
    id: Uniquifier = 0, 
    ui := ui_handle
) -> bool {
    trigger, bounds := trigger_(ui, loc, id)
    color := toggled ? utils.blend_two_colors(on_color, rl.WHITE, 0.50) : utils.blend_two_colors(off_color, rl.WHITE, 0.50)
    fill_rect(ui, color, bounds)
    if trigger != .NotActive { outline_rect(ui, rl.BLACK, bounds) }
    return trigger == .Clicked
}
