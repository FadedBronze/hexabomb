package network

import "core:net"
import "core:time"
import "core:encoding/cbor"
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

Network :: struct {
    // Ids
    mask: net.IP4_Address,
    discovery: net.UDP_Socket,
    socket: net.UDP_Socket,
    myEndpoint: net.Endpoint,

    // Recieved State
    throttle_info: box.SmallMap(64, typeid, ThrottleInfo),
    
    // Flags
    singleMachineTesting: bool,    
    loggingEnabled: bool,

    input_sender: InputSender,
    lobby_manager: LobbyManager,
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
    network.loggingEnabled = true
 
    init_input_send(network)
    init_lobby(network)
    
    return true
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

recieve_messages :: proc(network: ^Network) -> bool {
    for {
        broadcast: Packet
        err := poll_message(&broadcast, network)
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
            handle_input_packet(network, &b)
        case LobbyPacket:
            handle_lobby_packet(network, &b)
        }
    }
    return true
}

recieve_discovery_messages :: proc(network: ^Network) -> bool {
    for {
        broadcast: DiscoveryPacket
        err := poll_discovery_message(&broadcast, network)
        switch err {
            case nil:
            case .Would_Block:
                return true
            case:
                log.msg("error", err)
                return false
        }
        master := client_is_lobby_master(network)
        switch &v in &broadcast {
        case BroadcastLobbyEntry:
            if network.lobby_manager.state == .Connecting {
                retrieve_lobby_entries(network, &v)
            }
        }
    }
}

PollErr :: union {
    net.UDP_Recv_Error,
    cbor.Unmarshal_Error,
}

poll_discovery_message :: proc(packet: ^$T, network: ^Network) -> PollErr {
    return poll_message_(packet, network, network.discovery)
}

poll_message :: proc(packet: ^$T, network: ^Network) -> PollErr {
    return poll_message_(packet, network, network.socket)
}

poll_message_ :: proc(packet: ^$T, network: ^Network, socket: net.UDP_Socket) -> (err: PollErr) {
    buf: [1024]u8
    
    length, _ := net.recv_udp(socket, buf[:]) or_return

    cbor.unmarshal_from_bytes(buf[:length], packet, allocator = context.temp_allocator) or_return
    
    if network.loggingEnabled {
        log.msg("network", "RECIEVED", packet)
    }
    
    return err
}

broadcast_discovery_packet :: proc(
    network: ^Network, 
    packet: any, 
) -> bool {
    broadcast_msg := "BROADCAST DISCOVERY"

    if network.loggingEnabled {
        log.msg("network", broadcast_msg, packet)
    }

    payload, err := cbor.marshal_into_bytes(packet, allocator = context.temp_allocator)

    if err != nil {
        log.msg("error", err)
        return false
    }

    broadcast := apply_subnet_mask(network.myEndpoint.address.(net.IP4_Address), network.mask)

    for DISCOVERY_PORT in DISCOVERY_PORTS {
        net.send_udp(network.discovery, payload, {
            address = network.singleMachineTesting ? net.IP4_Address{127, 0, 0, 255} : broadcast,
            port = DISCOVERY_PORT,
        })
    }

    return true
}

broadcast_packet :: proc(
    network: ^Network, 
    packet: any, 
    target: net.Endpoint,
) -> bool {
    broadcast_msg := "BROADCAST"

    if network.loggingEnabled {
        log.msg("network", broadcast_msg, packet)
    }

    payload, err := cbor.marshal_into_bytes(packet, allocator = context.temp_allocator)

    if err != nil {
        log.msg("error", err)
        return false
    }

    _, err_ := net.send_udp(network.socket, payload, target)

    if err_ != nil {
        log.msg("error", err_)
        return false
    }       

    return true
}
