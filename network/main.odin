package network

import "core:net"
import "core:time"
import "core:container/queue"
import "core:encoding/cbor"
import sm "core:container/small_array"
import "../utils/"

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

BroadcastInputFrame :: struct($I: typeid) {
    inputFrame: I,
    frameNumber: u64,
    endpoint: net.Endpoint,
}

NotifyRecievedInputFrame :: struct {
    frameNumber: u64,
    endpoint: net.Endpoint,
}

Packet :: union($InputFrame: typeid) {
    NotifyRecievedInputFrame,
    BroadcastInputFrame(InputFrame),
    BroadcastLobbyStartGame,
    BroadcastLobbyEntry,
    RequestLobbyJoin,
    BroadcastLobbyInfo,
}

PacketType :: enum {
    NotifyRecievedInputFrame,
    BroadcastInputFrame,
    BroadcastLobbyStartGame,
    BroadcastLobbyEntry,
    RequestLobbyJoin,
    BroadcastLobbyInfo,
}

get_packet_type :: proc(packet: ^Packet($I)) -> PacketType {
    switch v in packet {
    case NotifyRecievedInputFrame:
        return .NotifyRecievedInputFrame
    case BroadcastInputFrame(I):
        return .BroadcastInputFrame
    case BroadcastLobbyStartGame:
        return .BroadcastLobbyStartGame
    case BroadcastLobbyEntry:
        return .BroadcastLobbyEntry
    case RequestLobbyJoin:
        return .RequestLobbyJoin
    case BroadcastLobbyInfo:
        return .BroadcastLobbyInfo
    }

    unreachable()
}

throttle_ms := [PacketType]u16 {
    .NotifyRecievedInputFrame = 5,
    .BroadcastInputFrame = 20,
    .BroadcastLobbyStartGame = 500,
    .BroadcastLobbyEntry = 1000,
    .RequestLobbyJoin = 0,
    .BroadcastLobbyInfo = 0,
}

Client :: struct {
    endpoint: net.Endpoint,
    name: string,
}

InputFrameSent :: struct($I: typeid) {
    sentTo: [MAX_CLIENTS]bool,
    frameNumber: u64,
    inputFrame: I,
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

Network :: struct($I: typeid) {
    // UI
    state: NetworkState,
    currentInputFrameState: I,
    lastInputFrameState: I,

    // Networking
    mask: net.IP4_Address,
    discovery: net.UDP_Socket,
    socket: net.UDP_Socket,

    // Recieved State
    lobbyEntries: sm.Small_Array(MAX_LOBBIES, LobbyEntry),
    lastBroadcastTimes: [PacketType]time.Time,

    lobby: Lobby,
    myEndpoint: net.Endpoint,
    
    inputQueue: queue.Queue(InputFrameSent(I)),

    prevInputFrames: [MAX_CLIENTS]I,
    inputFrames: [MAX_CLIENTS]I,
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

find_available_discovery_port :: proc(network: ^Network($I)) -> (ok: bool, discoveryPort: int, discovery: net.UDP_Socket) {
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

init :: proc(network: ^Network($T), port: int, singleMachineTesting: bool) -> (success: bool) { 
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
    
    return true
}

create_local_lobby :: proc(network: ^Network($I), name: string) {
    network.lobby = Lobby {
        creatorIdx = 0,
        clientCount = 1,
        name = name,
    }

    network.lobby.clients[0] = Client {
        endpoint = network.myEndpoint,
    }
}

create_lobby :: proc(network: ^Network($I), name: string) {
    create_local_lobby(network, name)
    broadcast_my_lobby_entry(network)
}

get_client_player_idx :: proc(network: ^Network($I)) -> u8 {
    assert(network.lobby.clientCount != 0)
    return get_endpoint_player_idx(network, network.myEndpoint)
}

get_endpoint_player_idx :: proc(network: ^Network($I), endpoint: net.Endpoint) -> u8 {
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

is_throttled :: proc(network: ^Network($I), type: PacketType) -> bool {
    now := time.now()
    
    if time.diff(network.lastBroadcastTimes[type], now) > time.Millisecond * auto_cast throttle_ms[type] {
        network.lastBroadcastTimes[type] = now
        return false
    }
    return true
}

request_join_lobby :: proc(network: ^Network($I), endpoint: net.Endpoint) -> bool {
    packet := Packet(I)(RequestLobbyJoin {
        endpoint = network.myEndpoint,
    })

    return broadcast_packet(network, &packet, target = endpoint)
}

fmt_lobby_name :: proc(buf: []u8, lobby: ^LobbyEntry) -> string {
    return utils.concatenate(buf[:], net.endpoint_to_string(lobby.endpoint), " | ", lobby.name)
}

client_is_lobby_master :: proc(network: ^Network($I)) -> bool {
    return network.lobby.clients[network.lobby.creatorIdx].endpoint == network.myEndpoint
}

retrieve_lobby_entries :: proc(network: ^Network($I), broadcast: ^BroadcastLobbyEntry) {
    for i in 0..<network.lobbyEntries.len {
        lobbyEntry := network.lobbyEntries.data[i]

        if lobbyEntry.endpoint == broadcast.entry.endpoint {
            return
        }
    }

    sm.append_elem(&network.lobbyEntries, broadcast.entry)
}

recieve_discovery_messages :: proc(network: ^Network($I)) -> bool {
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
        
        broadcast: Packet(I)
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

accept_lobby_info :: proc(network: ^Network($I), broadcast: ^BroadcastLobbyInfo) {
    network.lobby = broadcast.lobby
    network.state = .InLobby
}

accept_join_lobby :: proc(network: ^Network($I), broadcast: ^RequestLobbyJoin) {
    network.lobby.clients[network.lobby.clientCount] = Client {
        endpoint = broadcast.endpoint,
    }

    network.lobby.clientCount += 1
    
    broadcast_my_lobby_info(network, broadcast.endpoint)
}

all_inputs_uptodate :: proc(network: ^Network($I)) -> bool {
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

recieve_messages :: proc(network: ^Network($I)) -> bool {
    buf: [256]u8

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

        broadcast: Packet(I)
        {
            err := cbor.unmarshal_from_bytes(buf[:], &broadcast, allocator = context.temp_allocator)

            if err != nil {
                log.msg("error", err)
                return false
            }
        }

        master := client_is_lobby_master(network)

        switch &v in broadcast {
        case BroadcastLobbyInfo:
            if !master && (network.state == .WaitingForLobbyInfo || network.state == .InLobby) {
                accept_lobby_info(network, &v)
            }
        case NotifyRecievedInputFrame:
            recieve_input_recieved_broadcast(network, &v)
        case BroadcastInputFrame(I):
            recieve_input_state(network, &v)
        case BroadcastLobbyStartGame:
            if network.state == .InLobby {
                network.state = .Connected
            }
        case RequestLobbyJoin:
            if master && network.state == .InLobby {
                accept_join_lobby(network, &v)
            }
        case BroadcastLobbyEntry:
        }
    }

    return true
}

recieve_input_state :: proc(network: ^Network($I), broadcastInputFrame: ^BroadcastInputFrame(I)) {
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

recieve_input_recieved_broadcast :: proc(network: ^Network($I), broadcast: ^NotifyRecievedInputFrame) {
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

broadcast_input_state :: proc(network: ^Network($I)) -> bool {
    q := &network.inputQueue

    if is_throttled(network, .BroadcastInputFrame) {
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

        packet := Packet(I)(BroadcastInputFrame(I) {
            inputFrame = firstInput.inputFrame,
            endpoint = network.myEndpoint,
            frameNumber = firstInput.frameNumber,
        })
        
        broadcast_packet(network, &packet, network.lobby.clients[i].endpoint)
    }

    log.msg("debug", firstInput.frameNumber)
    
    if u8(sentCount) == network.lobby.clientCount-1 {
        queue.pop_front(&network.inputQueue)
    }    

    return true
}

broadcast_my_lobby_info :: proc(network: ^Network($I), target: net.Endpoint) {
    assert(client_is_lobby_master(network))

    packet := Packet(I)(BroadcastLobbyInfo {
        lobby = network.lobby,
    })
    
    if is_throttled(network, .BroadcastLobbyInfo) {
        return
    }

    broadcast_packet(network, &packet, target = target)
}

broadcast_game_start :: proc(network: ^Network($I)) -> bool {
    packet := Packet(I)(BroadcastLobbyStartGame {})

    if is_throttled(network, .BroadcastLobbyStartGame) {
        return true
    }
    
    for i in 0..<network.lobby.clientCount {
        broadcast_packet(network, &packet, network.lobby.clients[i].endpoint) or_return
    }

    return true
}

broadcast_my_lobby_entry :: proc(network: ^Network($I)) -> bool {
    assert(network.lobby.clientCount != 0)
    assert(client_is_lobby_master(network))

    packet := Packet(I)(BroadcastLobbyEntry {
        entry = LobbyEntry {
            endpoint = network.myEndpoint,
            name = network.lobby.name,
        }
    })

    if is_throttled(network, .BroadcastLobbyEntry) {
        return true
    }
    
    broadcast_packet(network, &packet)

    return true
}

broadcast_packet :: proc(
    network: ^Network($I), 
    packet: ^Packet(I), 
    target: net.Endpoint = {}
) -> bool {
    discovery := target == {}
    broadcast_msg := discovery ? "BROADCAST DISCOVERY" : "BROADCAST"

    if network.loggingEnabled {
        log.msg("network", broadcast_msg, packet)
    }

    payload, err := cbor.marshal_into_bytes(packet^, allocator = context.temp_allocator)

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

broadcast_recieved_input_state :: proc(network: ^Network($I), frameNumber: u64, endpoint: net.Endpoint) -> bool {
    packet := Packet(I)(NotifyRecievedInputFrame {
        frameNumber = frameNumber,
        endpoint = network.myEndpoint,
    })

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

incrementFrameNumber :: proc(network: ^Network($I), inputState: ^I) {
    network.inputFrameCount += 1
    network.lastInputFrameState = network.currentInputFrameState
    network.currentInputFrameState = inputState^

    queue.push_back(&network.inputQueue, InputFrameSent(I) {
        inputFrame = network.currentInputFrameState,
        frameNumber = network.inputFrameCount,
        sentTo = {},
    })
}
