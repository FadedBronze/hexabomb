package network

import "core:time"
import box "../containers"
import "../log"

MAX_LOBBIES :: 4
MAX_CLIENTS :: 4
DISCOVERY_PORTS := [3]int{4000, 4001, 4002}
MAX_NAME_CHARS :: 32

InputPacket :: union {
    NotifyRecievedInputFrame,
    BroadcastInputFrame,
}

Packet :: union {
    LobbyPacket,
    InputPacket,
}

DiscoveryPacket :: union {
    BroadcastLobbyEntry
}

ThrottleInfo :: struct {
    last_sent: time.Time,
    delay_ms: u16,
}

ThrottleMap :: box.SmallMap(64, typeid, ThrottleInfo)

register :: proc(throttles: ^ThrottleMap, T: typeid, throttle_ms: u16 = 0) {
    now := time.now()
    box.sm_set(throttles, T, ThrottleInfo{ now, throttle_ms })
}

Network :: struct {
    // Recieved State
    throttle_info: ThrottleMap,
    
    // Flags
    singleMachineTesting: bool,    

    input_sender: InputSender,
    lobby_manager: LobbyManager,
    base: NetworkBase,
}

init :: proc(network: ^Network, port: int, singleMachineTesting: bool) -> bool {
    network.singleMachineTesting = singleMachineTesting
 
    init_input_send(network) or_return
    init_lobby(&network.lobby_manager, &network.throttle_info)
    init_base(&network.base, port, singleMachineTesting) or_return

    return true
}

recieve_messages :: proc(network: ^Network) -> bool {
    for {
        broadcast: Packet
        err := poll_message(&broadcast, network.base)
        switch err {
            case nil:
            case .Would_Block:
                return true
            case:
                log.msg("error", err)
                return false
        }
        switch &b in broadcast {
        case InputPacket:
            handle_input_packet(&network.input_sender, &network.lobby_manager, network.base, &b)
        case LobbyPacket:
            handle_lobby_packet(&network.lobby_manager, &network.throttle_info, network.base, &b)
        }
    }
    return true
}

recieve_discovery_messages :: proc(network: ^Network) -> bool {
    for {
        broadcast: DiscoveryPacket
        err := poll_discovery_message(&broadcast, network.base)
        switch err {
            case nil:
            case .Would_Block:
                return true
            case:
                log.msg("error", err)
                return false
        }
        master := client_is_lobby_master(&network.lobby_manager, network.base)
        switch &v in &broadcast {
        case BroadcastLobbyEntry:
            if network.lobby_manager.state == .Connecting {
                retrieve_lobby_entries(&network.lobby_manager, network.base, &v)
            }
        }
    }
}
