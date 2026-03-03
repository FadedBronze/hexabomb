package network

import "../ui"
import "core:container/queue"
import box "../containers"
import "core:time"
import "core:net"
import "../log"
import "core:encoding/cbor"

BroadcastInputFrame :: struct {
    inputFrame: ui.InputState,
    frameNumber: u64,
    endpoint: net.Endpoint,
}

NotifyRecievedInputFrame :: struct {
    frameNumber: u64,
    endpoint: net.Endpoint,
}

InputSender :: struct {
    currentInputFrameState: ui.InputState,
    lastInputFrameState: ui.InputState,
    
    prevInputFrames: [MAX_CLIENTS]ui.InputState,
    inputFrames: [MAX_CLIENTS]ui.InputState,
    currentInputFrameNumbers: [MAX_CLIENTS]u64,

    inputFrameCount: u64,
    inputQueue: queue.Queue(InputFrameSent),
}

InputFrameSent :: struct {
    sentTo: [MAX_CLIENTS]bool,
    frameNumber: u64,
    inputFrame: ui.InputState,
}

init_input_send :: proc(network: ^Network) -> bool {
    err := queue.init(&network.input_sender.inputQueue)
    if err != nil {
        log.msg("error", err)
        return false
    }
    
    now := time.now()

    register(&network.base, BroadcastInputFrame, 5)
    register(&network.base, NotifyRecievedInputFrame, 5)

    return true
}

all_inputs_uptodate :: proc(input_sender: ^InputSender, lobby_manager: ^LobbyManager, base: ^NetworkBase) -> bool {
    if input_sender.inputQueue.len != 0 {
        return false
    }

    for i in 0..<lobby_manager.lobby.clientCount {
        if i == get_client_player_idx(lobby_manager, base) {
            continue
        }
        
        if input_sender.currentInputFrameNumbers[i] != input_sender.inputFrameCount {
            return false
        }
    }

    return true
}

recieve_input_state :: proc(input_sender: ^InputSender, lobby_manager: ^LobbyManager, base: ^NetworkBase, broadcastInputFrame: ^BroadcastInputFrame) {
    idx := get_endpoint_player_idx(lobby_manager, base, broadcastInputFrame.endpoint)

    currentFrameNumber := input_sender.inputFrameCount
    newFrameNumber := broadcastInputFrame.frameNumber

    if newFrameNumber == currentFrameNumber-1 {
        log.msg("debug", newFrameNumber, currentFrameNumber)
        broadcast_recieved_input_state(input_sender, base, broadcastInputFrame.frameNumber, broadcastInputFrame.endpoint)
    }
    
    if newFrameNumber != currentFrameNumber {
        return
    }

    if input_sender.currentInputFrameNumbers[idx] != input_sender.inputFrameCount-1 {
        return
    }

    input_sender.prevInputFrames[idx] = input_sender.inputFrames[idx]
    input_sender.inputFrames[idx] = broadcastInputFrame.inputFrame
    input_sender.currentInputFrameNumbers[idx] = broadcastInputFrame.frameNumber
    
    broadcast_recieved_input_state(input_sender, base, broadcastInputFrame.frameNumber, broadcastInputFrame.endpoint)
}

recieve_input_recieved_broadcast :: proc(
    input_sender: ^InputSender, 
    lobby_manager: ^LobbyManager, 
    base: ^NetworkBase, 
    broadcast: ^NotifyRecievedInputFrame
) {
    if input_sender.inputQueue.len == 0 {
        return
    }

    firstInput := queue.front_ptr(&input_sender.inputQueue)
    
    log.msg("debug", firstInput.frameNumber, broadcast.frameNumber)

    if firstInput.frameNumber != broadcast.frameNumber {
        return
    }

    idx := get_endpoint_player_idx(lobby_manager, base, broadcast.endpoint)
    firstInput.sentTo[idx] = true
}

broadcast_input_state :: proc(input_sender: ^InputSender, lobby_manager: ^LobbyManager, base: ^NetworkBase) -> bool {
    q := &input_sender.inputQueue

    if is_throttled(base, BroadcastInputFrame) {
        return true
    }
    
    if q.len == 0 {
        return true
    }

    firstInput := queue.front_ptr(q)

    sentCount := 0
    
    for i in 0..<lobby_manager.lobby.clientCount {
        if i == get_client_player_idx(lobby_manager, base) {
            continue
        }

        sent := firstInput.sentTo[i]

        if sent {
            sentCount += 1
            continue
        }

        packet := Packet(InputPacket(BroadcastInputFrame {
            inputFrame = firstInput.inputFrame,
            endpoint = base.myEndpoint,
            frameNumber = firstInput.frameNumber,
        }))
        
        broadcast_packet(base, packet, lobby_manager.lobby.clients[i].endpoint)
    }

    if u8(sentCount) == lobby_manager.lobby.clientCount-1 {
        queue.pop_front(&input_sender.inputQueue)
    }    

    return true
}

incrementFrameNumber :: proc(input_sender: ^InputSender, inputState: ^ui.InputState) {
    input_sender.inputFrameCount += 1
    input_sender.lastInputFrameState = input_sender.currentInputFrameState
    input_sender.currentInputFrameState = inputState^

    queue.push_back(&input_sender.inputQueue, InputFrameSent {
        inputFrame = input_sender.currentInputFrameState,
        frameNumber = input_sender.inputFrameCount,
        sentTo = {},
    })
}

handle_input_packet :: proc(input_sender: ^InputSender, lobby_manager: ^LobbyManager, base: ^NetworkBase, b: ^InputPacket) {
    switch &v in b {
    case NotifyRecievedInputFrame:
        recieve_input_recieved_broadcast(input_sender, lobby_manager, base, &v)
    case BroadcastInputFrame:
        recieve_input_state(input_sender, lobby_manager, base, &v)
    }
}

broadcast_recieved_input_state :: proc(input_sender: ^InputSender, base: ^NetworkBase, frameNumber: u64, endpoint: net.Endpoint) -> bool {
    packet := Packet(InputPacket(NotifyRecievedInputFrame {
        frameNumber = frameNumber,
        endpoint = base.myEndpoint,
    }))

    bytes, err := cbor.marshal_into_bytes(packet, allocator = context.temp_allocator)
    
    if err != nil {
        log.msg("error", err)
        return false
    }

    {
        _, err := net.send_udp(base.socket, bytes, endpoint)

        if err != nil {
            log.msg("error", err)
            return false
        }
    }

    return true
}
