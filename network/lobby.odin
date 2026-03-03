package network

import "core:net"
import sm "core:container/small_array"
import "core:time"
import "core:strings"
import "../utils/"

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

LobbyPacket :: union {
    BroadcastLobbyStartGame,
    RequestLobbyJoin,
    BroadcastLobbyInfo,
}

Client :: struct {
    endpoint: net.Endpoint,
    name: string,
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

LobbyManager :: struct {
    state: NetworkState,
    lobbyEntries: sm.Small_Array(MAX_LOBBIES, LobbyEntry),
    lobby: Lobby,
    base: ^NetworkBase,
}

init_lobby :: proc(lobby_manager: ^LobbyManager, base: ^NetworkBase) {
    lobby_manager.lobby = {}
    
    now := time.now()
    register(base, BroadcastLobbyEntry, 500)
    register(base, BroadcastLobbyInfo, 500)
    register(base, BroadcastLobbyStartGame, 500)
    register(base, RequestLobbyJoin, 500)

    lobby_manager.base = base
}

create_local_lobby :: proc(lobby_manager: ^LobbyManager, name: string) {
    base := lobby_manager.base
    lobby_manager.lobby = Lobby {
        creatorIdx = 0,
        clientCount = 1,
        name = name,
    }

    lobby_manager.lobby.clients[0] = Client {
        endpoint = base.myEndpoint,
    }
}

create_lobby :: proc(lobby_manager: ^LobbyManager, name: string, singleMachineTesting := false) {
    base := lobby_manager.base
    create_local_lobby(lobby_manager, name)
    broadcast_my_lobby_entry(lobby_manager, singleMachineTesting)
}

get_client_player_idx :: proc(lobby_manager: ^LobbyManager) -> u8 {
    base := lobby_manager.base
    assert(lobby_manager.lobby.clientCount != 0)
    return get_endpoint_player_idx(lobby_manager, base.myEndpoint)
}

get_endpoint_player_idx :: proc(lobby_manager: ^LobbyManager, endpoint: net.Endpoint) -> u8 {
    for client, i in lobby_manager.lobby.clients[:lobby_manager.lobby.clientCount] {
        if client.endpoint == endpoint {
            return u8(i)
        }
    }

    return MAX_CLIENTS
}

client_is_lobby_master :: proc(lobby_manager: ^LobbyManager) -> bool {
    base := lobby_manager.base
    return lobby_manager.lobby.clients[lobby_manager.lobby.creatorIdx].endpoint == base.myEndpoint
}

retrieve_lobby_entries :: proc(lobby_manager: ^LobbyManager, broadcast: ^BroadcastLobbyEntry) {
    for i in 0..<lobby_manager.lobbyEntries.len {
        lobbyEntry := lobby_manager.lobbyEntries.data[i]

        if lobbyEntry.endpoint == broadcast.entry.endpoint {
            return
        }
    }

    entry := broadcast.entry
    entry.name = strings.concatenate({entry.name})

    sm.append_elem(&lobby_manager.lobbyEntries, entry)
}

broadcast_my_lobby_info :: proc(lobby_manager: ^LobbyManager, target: net.Endpoint) {
    base := lobby_manager.base
    assert(client_is_lobby_master(lobby_manager))
    packet := Packet(LobbyPacket(BroadcastLobbyInfo {
        lobby = lobby_manager.lobby,
    }))
    if is_throttled(base, BroadcastLobbyInfo) {
        return
    }
    broadcast_packet(base, packet, target)
}

broadcast_game_start :: proc(lobby_manager: ^LobbyManager) -> bool {
    base := lobby_manager.base
    packet := Packet(LobbyPacket(BroadcastLobbyStartGame {}))
    if is_throttled(base, BroadcastLobbyStartGame) {
        return true
    }
    for i in 0..<lobby_manager.lobby.clientCount {
        broadcast_packet(base, packet, lobby_manager.lobby.clients[i].endpoint) or_return
    }
    return true
}

broadcast_my_lobby_entry :: proc(lobby_manager: ^LobbyManager, singleMachineTesting := false) -> bool {
    base := lobby_manager.base
    assert(lobby_manager.lobby.clientCount != 0)
    assert(client_is_lobby_master(lobby_manager))
    packet := DiscoveryPacket(BroadcastLobbyEntry {
        entry = LobbyEntry {
            endpoint = base.myEndpoint,
            name = lobby_manager.lobby.name,
        }
    })
    if is_throttled(base, BroadcastLobbyEntry) {
        return true
    }
    broadcast_discovery_packet(base, packet, singleMachineTesting)
    return true
}

accept_join_lobby :: proc(lobby_manager: ^LobbyManager, broadcast: ^RequestLobbyJoin) {
    lobby_manager.lobby.clients[lobby_manager.lobby.clientCount] = Client {
        endpoint = broadcast.endpoint,
    }
    lobby_manager.lobby.clientCount += 1
    broadcast_my_lobby_info(lobby_manager, broadcast.endpoint)
}

request_join_lobby :: proc(lobby_manager: ^LobbyManager, endpoint: net.Endpoint) -> bool {
    base := lobby_manager.base
    packet := Packet(LobbyPacket(
        RequestLobbyJoin {
            endpoint = base.myEndpoint,
        }
    ))
    return broadcast_packet(base, packet, target = endpoint)
}

fmt_lobby_name :: proc(buf: []u8, lobby: ^LobbyEntry) -> string {
    return utils.concatenate(buf[:], net.endpoint_to_string(lobby.endpoint), " | ", lobby.name)
}

handle_lobby_packet :: proc(lobby_manager: ^LobbyManager, packet: ^LobbyPacket) {
    base := &lobby_manager.base
    master := client_is_lobby_master(lobby_manager)

    switch &v in packet {
    case BroadcastLobbyInfo:
        if !master && (lobby_manager.state == .WaitingForLobbyInfo || lobby_manager.state == .InLobby) {
            lobby_manager.lobby = v.lobby
            lobby_manager.state = .InLobby
        }
    case BroadcastLobbyStartGame:
        if lobby_manager.state == .InLobby {
            lobby_manager.state = .Connected
        }
    case RequestLobbyJoin:
        if master && lobby_manager.state == .InLobby {
            accept_join_lobby(lobby_manager, &v)
        }
    }
}

import rl "vendor:raylib"
import "../ui"

update_network_interface :: proc(network: ^Network) { 
    ui.flat_color(rl.Color{ 0, 0, 0, 20 })
    
    switch network.lobby_manager.state {
    case .Failed:
        ui.add_layout(ui.margin_xy(75, 75, relativity=.FromCenter))
        ui.add_bounds()
        try_again := ui.button("Network error: try again?", rl.GRAY)
        ui.pop_bounds()
        ui.pop_layout()

        if try_again {
            network.lobby_manager.state = .InLobby
        }
    case .Connected:
    case .WaitingForLobbyInfo:
        if (!recieve_messages(network)) {
            network.lobby_manager.state = .Failed
            return
        }
    case .InLobby:
        if (!recieve_messages(network)) {
            network.lobby_manager.state = .Failed
            return
        }

        buf: [2]u8
        buf[0] = network.lobby_manager.lobby.clientCount + '0'
        buf[1] = '\x00'
        rl.DrawText(transmute(cstring)raw_data(buf[:]), 10, 10, 24, rl.WHITE)

        if client_is_lobby_master(&network.lobby_manager) {
            if !broadcast_my_lobby_entry(&network.lobby_manager, network.singleMachineTesting) {
                network.lobby_manager.state = .Failed
                return
            }

            recieve_discovery_messages(network)

            ui.add_layout(ui.margin_xy(75, 75, relativity=.FromCenter))
            ui.add_bounds()
            start := ui.button("start", rl.GRAY)
            ui.pop_bounds()
            ui.pop_layout()

            if start {
                network.lobby_manager.state = .Connected
                if !broadcast_game_start(&network.lobby_manager) {
                    network.lobby_manager.state = .Failed
                    return
                } 
            }    
        }
    case .Connecting:
        if (!recieve_discovery_messages(network)) {
            network.lobby_manager.state = .Failed
            return
        }

        ui.add_layout(ui.margin_xy(75, 150, relativity=.FromCenter))

        ui.add_bounds()
        
        ui.add_layout(ui.FlexBox {
            gap = 10,
            direction = .Vertical,
            corner = {.Left, .Top}
        })

        lobby_count := network.lobby_manager.lobbyEntries.len

        for i in 0..<u64(4) {
            buf: [64]u8
            ui.add_bounds({ 150, 50 })
            if ui.button(
                lobby_count > int(i) ? fmt_lobby_name(buf[:], &network.lobby_manager.lobbyEntries.data[i]) : "--", 
                rl.GRAY, 
                id = i
            ) && lobby_count > int(i) {
                if (!request_join_lobby(&network.lobby_manager, network.lobby_manager.lobbyEntries.data[i].endpoint)) {
                    network.lobby_manager.state = .Failed
                    return
                }
                network.lobby_manager.state = .WaitingForLobbyInfo
            }
            ui.pop_bounds()
        }

        ui.add_bounds({150, 50})
        create_room := ui.button("create room", rl.GRAY)
        ui.pop_bounds()
        ui.pop_layout()

        ui.pop_bounds()
        ui.pop_layout()

        if (create_room) {
            create_lobby(&network.lobby_manager, "the room", network.singleMachineTesting)
            network.lobby_manager.state = .InLobby
        }
    }        
}
