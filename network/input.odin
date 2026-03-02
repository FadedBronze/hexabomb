package network

import "../ui"
import "core:container/queue"
import box "../containers"
import "core:time"
import "core:net"
import "../log"

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

init_input_send :: proc(network: ^Network) {
    queue.init(&network.input_sender.inputQueue)
    
    now := time.now()
    box.sm_set(&network.throttle_info, BroadcastInputFrame, ThrottleInfo{ now, 5 })
    box.sm_set(&network.throttle_info, NotifyRecievedInputFrame, ThrottleInfo{ now, 5 })
}

all_inputs_uptodate :: proc(network: ^Network) -> bool {
    input_sender := &network.input_sender

    if input_sender.inputQueue.len != 0 {
        return false
    }

    for i in 0..<network.lobby.clientCount {
        if i == get_client_player_idx(network) {
            continue
        }
        
        if input_sender.currentInputFrameNumbers[i] != input_sender.inputFrameCount {
            return false
        }
    }

    return true
}

recieve_input_state :: proc(network: ^Network, broadcastInputFrame: ^BroadcastInputFrame) {
    idx := get_endpoint_player_idx(network, broadcastInputFrame.endpoint)
    input_sender := &network.input_sender

    currentFrameNumber := input_sender.inputFrameCount
    newFrameNumber := broadcastInputFrame.frameNumber

    if newFrameNumber == currentFrameNumber-1 {
        log.msg("debug", newFrameNumber, currentFrameNumber)
        broadcast_recieved_input_state(network, broadcastInputFrame.frameNumber, broadcastInputFrame.endpoint)
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
    
    broadcast_recieved_input_state(network, broadcastInputFrame.frameNumber, broadcastInputFrame.endpoint)
}

recieve_input_recieved_broadcast :: proc(network: ^Network, broadcast: ^NotifyRecievedInputFrame) {
    input_sender := &network.input_sender

    if input_sender.inputQueue.len == 0 {
        return
    }

    firstInput := queue.front_ptr(&input_sender.inputQueue)
    
    log.msg("debug", firstInput.frameNumber, broadcast.frameNumber)

    if firstInput.frameNumber != broadcast.frameNumber {
        return
    }

    idx := get_endpoint_player_idx(network, broadcast.endpoint)
    firstInput.sentTo[idx] = true
}

broadcast_input_state :: proc(network: ^Network) -> bool {
    input_sender := &network.input_sender

    q := &input_sender.inputQueue

    if is_throttled(network, BroadcastInputFrame) {
        return true
    }
    
    if q.len == 0 {
        return true
    }

    firstInput := queue.front_ptr(q)

    sentCount := 0
    
    for i in 0..<network.lobby.clientCount {
        if i == get_client_player_idx(network) {
            continue
        }

        sent := firstInput.sentTo[i]

        if sent {
            sentCount += 1
            continue
        }

        packet := Packet(InputPacket(BroadcastInputFrame {
            inputFrame = firstInput.inputFrame,
            endpoint = network.myEndpoint,
            frameNumber = firstInput.frameNumber,
        }))
        
        broadcast_packet(network, packet, network.lobby.clients[i].endpoint)
    }

    if u8(sentCount) == network.lobby.clientCount-1 {
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
