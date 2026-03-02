package network

import "core:net"
import "core:time"
import "core:container/queue"
import "core:encoding/cbor"
import sm "core:container/small_array"
import box "../containers"
import "../utils/"
import "core:strings"
import "../log"

MAX_LOBBIES :: 4
MAX_CLIENTS :: 4
DISCOVERY_PORTS := [3]int{4000, 4001, 4002}
MAX_NAME_CHARS :: 32

BroadcastLobbyInfo :: struct {
    lobby: Lobby,
}

RequestLobbyJoin :: struct {
    endpoint: net.Endpoint,
} 

BroadcastLobbyEntry :: struct {
    entry: LobbyEntry,
}

BroadcastLobbyStartGame :: struct {}

BroadcastInputFrame :: struct {
    inputFrame: ui.InputState,
    frameNumber: u64,
    endpoint: net.Endpoint,
}

NotifyRecievedInputFrame :: struct {
    frameNumber: u64,
    endpoint: net.Endpoint,
}

LobbyPacket :: union {
    BroadcastLobbyStartGame,
    RequestLobbyJoin,
    BroadcastLobbyInfo,
}

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

Client :: struct {
    endpoint: net.Endpoint,
    name: string,
}

InputFrameSent :: struct {
    sentTo: [MAX_CLIENTS]bool,
    frameNumber: u64,
    inputFrame: ui.InputState,
}

Lobby :: struct {
    name: string,
    creatorIdx: u8,
    clientCount: u8,
    clients: [MAX_CLIENTS]Client,
}

LobbyEntry :: struct {
    endpoint: net.Endpoint,
    name: string,
}

NetworkState :: enum {
    Connecting,
    WaitingForLobbyInfo,
    InLobby,
    Connected,
    Failed,
}

ThrottleInfo :: struct {
    last_sent: time.Time,
    delay_ms: u16,
}

import "../ui"

Network :: struct {
    // UI
    state: NetworkState,
    currentInputFrameState: ui.InputState,
    lastInputFrameState: ui.InputState,

    // Networking
    mask: net.IP4_Address,
    discovery: net.UDP_Socket,
    socket: net.UDP_Socket,

    // Recieved State
    lobbyEntries: sm.Small_Array(MAX_LOBBIES, LobbyEntry),

    throttle_info: box.SmallMap(64, typeid, ThrottleInfo),

    lobby: Lobby,
    myEndpoint: net.Endpoint,
    
    inputQueue: queue.Queue(InputFrameSent),

    prevInputFrames: [MAX_CLIENTS]ui.InputState,
    inputFrames: [MAX_CLIENTS]ui.InputState,
    currentInputFrameNumbers: [MAX_CLIENTS]u64,

    inputFrameCount: u64,

    // Mode
    singleMachineTesting: bool,    
    loggingEnabled: bool,
}

import vl "core:mem/virtual"

find_device_ip :: proc(testing: bool) -> net.IP4_Address {
    addr := net.IP4_Loopback

    buf: [50000]u8
    arena: vl.Arena
    err := vl.arena_init_buffer(&arena, buf[:])
    assert(err == nil)

    if !testing {
        if ifaces, err := net.enumerate_interfaces(allocator = vl.arena_allocator(&arena)); err == .None {
            for iface in ifaces {
                for unicast in iface.unicast {
                    router := false

                    for gw in iface.gateways {
                        if gw == unicast.address {
                            router = true
                            break;
                        }
                    }

                    if router {
                        continue
                    }

                    if address, ok := unicast.address.(net.IP4_Address); ok {
                        if address[0] == 127 {
                            continue
                        }

                        if address[0] == 169 && address[1] == 254 { continue }

                        addr = address
                        break;
                    }
                }

                if addr != net.IP4_Loopback {
                    break;
                }
            }
        } else {
            log.msg("error", "Find device IP failed:", err)
            return net.IP4_Loopback
        }
    }

    if addr == net.IP4_Loopback {
        log.msg("error", "Find device IP failed")
        return net.IP4_Loopback
    }

    return addr
}

find_available_discovery_port :: proc(network: ^Network) -> (ok: bool, discoveryPort: int, discovery: net.UDP_Socket) {
    err2: net.Network_Error

    for DISCOVERY_PORT in DISCOVERY_PORTS[:] {
        discovery, err2 = net.make_bound_udp_socket(net.IP4_Any, DISCOVERY_PORT)

        if err2 != nil {
            if err2.(net.Bind_Error) == .Address_In_Use {
                continue
            }

            log.msg("error", "Find port failed:", err2)
            return false, 0, 0
        }

        ok = true
        discoveryPort = DISCOVERY_PORT
        break
    }

    if !ok {
        log.msg("error", "Find port failed: ports filled")
        return false, 0, 0
    }

    return ok, discoveryPort, discovery
}

init :: proc(network: ^Network, port: int, singleMachineTesting: bool) -> (success: bool) { 
    network.singleMachineTesting = singleMachineTesting
    addr := net.IP4_Loopback
    
    if !singleMachineTesting {
        addr = find_device_ip(singleMachineTesting)

        if addr == net.IP4_Loopback {
            log.msg("error", "Cannot broadcast on loopback; message stays local")
            return false
        }
    }
    
    sock, err := net.make_bound_udp_socket(net.IP4_Any, port)
    net.set_blocking(sock, false)

    if err != nil {
        log.msg("error", "Init network failed:", err)
        return false
    }

    ok, discoveryPort, discovery := find_available_discovery_port(network)
    
    if !ok {
        return false
    }

    log.msg("error", "discovery port:", discoveryPort, "port:", port, "address:", addr)

    err = net.set_blocking(discovery, false)
    if err != nil {
        log.msg("error", err)
        return false
    }
    
    network.discovery = discovery
    network.socket = sock
    network.myEndpoint = {
        address = addr,
        port = port,
    }
    network.mask = net.IP4_Address{255, 255, 255, 0}
    network.lobby = {}
    network.loggingEnabled = true
 
    queue.init(&network.inputQueue)

    now := time.now()
    box.sm_set(&network.throttle_info, BroadcastLobbyEntry, ThrottleInfo{ now, 500 })
    box.sm_set(&network.throttle_info, BroadcastLobbyInfo, ThrottleInfo{ now, 0 })
    box.sm_set(&network.throttle_info, BroadcastLobbyStartGame, ThrottleInfo{ now, 0 })
    box.sm_set(&network.throttle_info, RequestLobbyJoin, ThrottleInfo{ now, 0 })
    box.sm_set(&network.throttle_info, BroadcastInputFrame, ThrottleInfo{ now, 5 })
    box.sm_set(&network.throttle_info, NotifyRecievedInputFrame, ThrottleInfo{ now, 5 })
    
    return true
}

create_local_lobby :: proc(network: ^Network, name: string) {
    network.lobby = Lobby {
        creatorIdx = 0,
        clientCount = 1,
        name = name,
    }

    network.lobby.clients[0] = Client {
        endpoint = network.myEndpoint,
    }
}

create_lobby :: proc(network: ^Network, name: string) {
    create_local_lobby(network, name)
    broadcast_my_lobby_entry(network)
}

get_client_player_idx :: proc(network: ^Network) -> u8 {
    assert(network.lobby.clientCount != 0)
    return get_endpoint_player_idx(network, network.myEndpoint)
}

get_endpoint_player_idx :: proc(network: ^Network, endpoint: net.Endpoint) -> u8 {
    for client, i in network.lobby.clients[:network.lobby.clientCount] {
        if client.endpoint == endpoint {
            return u8(i)
        }
    }

    return MAX_CLIENTS
}

apply_subnet_mask :: proc(ip: net.IP4_Address, mask: net.IP4_Address) -> net.IP4_Address {
    broadcast := net.IP4_Address{}
    for i in 0..<4 {
        broadcast[i] = (ip[i] & mask[i]) | (~mask[i])
    }
    return broadcast
}

is_throttled :: proc(network: ^Network, T: typeid) -> bool {
    now := time.now()

    info := box.sm_get_ptr(&network.throttle_info, T)
    
    if time.diff(info.last_sent, now) > time.Millisecond * auto_cast info.delay_ms {
        info.last_sent = now
        return false
    }
    return true
}

request_join_lobby :: proc(network: ^Network, endpoint: net.Endpoint) -> bool {
    packet := Packet(LobbyPacket(
        RequestLobbyJoin {
            endpoint = network.myEndpoint,
        }
    ))

    return broadcast_packet(network, packet, target = endpoint)
}

fmt_lobby_name :: proc(buf: []u8, lobby: ^LobbyEntry) -> string {
    return utils.concatenate(buf[:], net.endpoint_to_string(lobby.endpoint), " | ", lobby.name)
}

client_is_lobby_master :: proc(network: ^Network) -> bool {
    return network.lobby.clients[network.lobby.creatorIdx].endpoint == network.myEndpoint
}

retrieve_lobby_entries :: proc(network: ^Network, broadcast: ^BroadcastLobbyEntry) {
    for i in 0..<network.lobbyEntries.len {
        lobbyEntry := network.lobbyEntries.data[i]

        if lobbyEntry.endpoint == broadcast.entry.endpoint {
            return
        }
    }

    entry := broadcast.entry
    entry.name = strings.concatenate({entry.name})

    sm.append_elem(&network.lobbyEntries, entry)
}

recieve_discovery_messages :: proc(network: ^Network) -> bool {
    buf: [256]u8
    
    for {
        length, _, err := net.recv_udp(network.discovery, buf[:])

        #partial switch err {
        case .Connection_Refused:
            continue
        case .Would_Block:
            return true
        case nil:
        case:
            log.msg("error", err)
            return false
        }
        
        broadcast: DiscoveryPacket
        {
            err := cbor.unmarshal_from_bytes(buf[:], &broadcast, allocator = context.temp_allocator)
            
            if err != nil {
                log.msg("error", err)
                return false
            }
        }
        
        if network.loggingEnabled {
            log.msg("network", "RECIEVED", broadcast)
        }
        
        master := client_is_lobby_master(network)

        #partial switch &v in &broadcast {
        case BroadcastLobbyEntry:
            if network.state == .Connecting {
                retrieve_lobby_entries(network, &v)
            }
        }
    }

    return true
}

accept_lobby_info :: proc(network: ^Network, broadcast: ^BroadcastLobbyInfo) {
    network.lobby = broadcast.lobby
    network.state = .InLobby
}

accept_join_lobby :: proc(network: ^Network, broadcast: ^RequestLobbyJoin) {
    network.lobby.clients[network.lobby.clientCount] = Client {
        endpoint = broadcast.endpoint,
    }

    network.lobby.clientCount += 1
    
    broadcast_my_lobby_info(network, broadcast.endpoint)
}

all_inputs_uptodate :: proc(network: ^Network) -> bool {
    if network.inputQueue.len != 0 {
        return false
    }

    for i in 0..<network.lobby.clientCount {
        if i == get_client_player_idx(network) {
            continue
        }
        
        if network.currentInputFrameNumbers[i] != network.inputFrameCount {
            return false
        }
    }

    return true
}

recieve_messages :: proc(network: ^Network) -> bool {
    buf: [512]u8

    for {
        {
            _, _, err := net.recv_udp(network.socket, buf[:])

            if err == .Would_Block {
                break
            }

            if err != nil {
                log.msg("error", err)
                return false
            }
        }
        
        broadcast: Packet
        {
            err := cbor.unmarshal_from_bytes(buf[:], &broadcast, allocator = context.temp_allocator)

            if err != nil {
                log.msg("error", err)
                return false
            }
        }

        master := client_is_lobby_master(network)
        
        switch &b in broadcast {
        case InputPacket:
            switch &v in b {
            case NotifyRecievedInputFrame:
                recieve_input_recieved_broadcast(network, &v)
            case BroadcastInputFrame:
                recieve_input_state(network, &v)
            }
        case LobbyPacket:
            switch &v in b {
            case BroadcastLobbyInfo:
                if !master && (network.state == .WaitingForLobbyInfo || network.state == .InLobby) {
                    accept_lobby_info(network, &v)
                }
            case BroadcastLobbyStartGame:
                if network.state == .InLobby {
                    network.state = .Connected
                }
            case RequestLobbyJoin:
                if master && network.state == .InLobby {
                    accept_join_lobby(network, &v)
                }
            }
        }
    }

    return true
}

recieve_input_state :: proc(network: ^Network, broadcastInputFrame: ^BroadcastInputFrame) {
    idx := get_endpoint_player_idx(network, broadcastInputFrame.endpoint)

    currentFrameNumber := network.inputFrameCount
    newFrameNumber := broadcastInputFrame.frameNumber

    if newFrameNumber == currentFrameNumber-1 {
        log.msg("debug", newFrameNumber, currentFrameNumber)
        broadcast_recieved_input_state(network, broadcastInputFrame.frameNumber, broadcastInputFrame.endpoint)
    }
    
    if newFrameNumber != currentFrameNumber {
        return
    }

    if network.currentInputFrameNumbers[idx] != network.inputFrameCount-1 {
        return
    }

    network.prevInputFrames[idx] = network.inputFrames[idx]
    network.inputFrames[idx] = broadcastInputFrame.inputFrame
    network.currentInputFrameNumbers[idx] = broadcastInputFrame.frameNumber
    
    broadcast_recieved_input_state(network, broadcastInputFrame.frameNumber, broadcastInputFrame.endpoint)
}

recieve_input_recieved_broadcast :: proc(network: ^Network, broadcast: ^NotifyRecievedInputFrame) {
    if network.inputQueue.len == 0 {
        return
    }

    firstInput := queue.front_ptr(&network.inputQueue)
    
    log.msg("debug", firstInput.frameNumber, broadcast.frameNumber)

    if firstInput.frameNumber != broadcast.frameNumber {
        return
    }

    idx := get_endpoint_player_idx(network, broadcast.endpoint)
    firstInput.sentTo[idx] = true
}

broadcast_input_state :: proc(network: ^Network) -> bool {
    q := &network.inputQueue

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
        queue.pop_front(&network.inputQueue)
    }    

    return true
}

broadcast_my_lobby_info :: proc(network: ^Network, target: net.Endpoint) {
    assert(client_is_lobby_master(network))

    packet := Packet(LobbyPacket(BroadcastLobbyInfo {
        lobby = network.lobby,
    }))
    
    if is_throttled(network, BroadcastLobbyInfo) {
        return
    }

    broadcast_packet(network, packet, target = target)
}

broadcast_game_start :: proc(network: ^Network) -> bool {
    packet := Packet(LobbyPacket(BroadcastLobbyStartGame {}))

    if is_throttled(network, BroadcastLobbyStartGame) {
        return true
    }
    
    for i in 0..<network.lobby.clientCount {
        broadcast_packet(network, packet, network.lobby.clients[i].endpoint) or_return
    }

    return true
}

broadcast_my_lobby_entry :: proc(network: ^Network) -> bool {
    assert(network.lobby.clientCount != 0)
    assert(client_is_lobby_master(network))

    packet := DiscoveryPacket(BroadcastLobbyEntry {
        entry = LobbyEntry {
            endpoint = network.myEndpoint,
            name = network.lobby.name,
        }
    })

    if is_throttled(network, BroadcastLobbyEntry) {
        return true
    }
    
    broadcast_packet(network, packet)

    return true
}

broadcast_packet :: proc(
    network: ^Network, 
    packet: any, 
    target: net.Endpoint = {}
) -> bool {
    discovery := target == {}
    broadcast_msg := discovery ? "BROADCAST DISCOVERY" : "BROADCAST"

    if network.loggingEnabled {
        log.msg("network", broadcast_msg, packet)
    }

    payload, err := cbor.marshal_into_bytes(packet, allocator = context.temp_allocator)

    if err != nil {
        log.msg("error", err)
        return false
    }

    if discovery {
        broadcast := apply_subnet_mask(network.myEndpoint.address.(net.IP4_Address), network.mask)

        for DISCOVERY_PORT in DISCOVERY_PORTS {
            net.send_udp(network.discovery, payload, {
                address = network.singleMachineTesting ? net.IP4_Address{127, 0, 0, 255} : broadcast,
                port = DISCOVERY_PORT,
            })
        }

    } else {
        _, err := net.send_udp(network.socket, payload, target)

        if err != nil {
            log.msg("error", err)
            return false
        }       
    }

    return true
}

broadcast_recieved_input_state :: proc(network: ^Network, frameNumber: u64, endpoint: net.Endpoint) -> bool {
    packet := Packet(InputPacket(NotifyRecievedInputFrame {
        frameNumber = frameNumber,
        endpoint = network.myEndpoint,
    }))

    bytes, err := cbor.marshal_into_bytes(packet, allocator = context.temp_allocator)
    
    if err != nil {
        log.msg("error", err)
        return false
    }

    {
        _, err := net.send_udp(network.socket, bytes, endpoint)

        if err != nil {
            log.msg("error", err)
            return false
        }
    }

    return true
}

incrementFrameNumber :: proc(network: ^Network, inputState: ^ui.InputState) {
    network.inputFrameCount += 1
    network.lastInputFrameState = network.currentInputFrameState
    network.currentInputFrameState = inputState^

    queue.push_back(&network.inputQueue, InputFrameSent {
        inputFrame = network.currentInputFrameState,
        frameNumber = network.inputFrameCount,
        sentTo = {},
    })
}
