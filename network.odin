package main

import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:time"
import "core:encoding/endian"

import rl "vendor:raylib"
import la "core:math/linalg"

MAX_LOBBIES :: 4
DISCOVERY_PORTS := [3]int{4000, 4001, 4002}
MAX_NAME_CHARS :: 32

LOBBY_INFO_PREFIX ::      "HXBLBINF_"
LOBBY_JOIN_PREFIX ::      "HXBLJOIN_"
LOBBY_ENTRY_PREFIX ::     "HXBENTRY_"
LOBBY_STARTGAME_PREFIX :: "HXBSTARG_"
PREFIX_SIZE :: len(LOBBY_INFO_PREFIX)

LOCAL_IP := net.IP4_Address{127, 0, 0, 1}
BROADCAST_IP := LOCAL_IP

Client :: struct {
  endpoint: net.Endpoint,
  name_len: u8,
  name_buf: [MAX_NAME_CHARS]u8
}

Lobby :: struct {
  name_len: u8,
  name_buf: [MAX_NAME_CHARS]u8,
  creatorIdx: u8,
  client_count: u8,
  clients: [MAX_PLAYERS]Client,
}

LobbyEntry :: struct {
  endpoint: net.Endpoint,
  name_buf: [MAX_NAME_CHARS]u8,
  name_len: u8,
}

NetworkState :: enum {
  Connecting,
  WaitingForLobbyInfo,
  InLobby,
  Connected,
}

Network :: struct {
  ui: UI,
  state: NetworkState,

  last_broadcast: time.Time,

  lobbyEntries: [MAX_LOBBIES]LobbyEntry,
  lobbyEntryCount: u8,

  discovery: net.UDP_Socket,
  socket: net.UDP_Socket,
  lobby: Lobby,
  myEndpoint: net.Endpoint,
}

init_network :: proc(network: ^Network) {
  port := 6969
  for arg in os.args {
    if strings.has_prefix(arg, "-p=") {
      port = strconv.atoi(arg[3:])
    }
  }

  // TODO
  addr := BROADCAST_IP

  sock, err := net.make_bound_udp_socket(addr, port)
  net.set_blocking(sock, false)
    
  fmt.println(port)

  if err != nil {
    fmt.println(err)
    assert(false)
  }
  
  discovery: net.UDP_Socket 
  foundPort: bool = false
  discoveryPort: int

  for DISCOVERY_PORT in DISCOVERY_PORTS[:] {
    err2: net.Network_Error 
    discovery, err2 = net.make_bound_udp_socket(addr, DISCOVERY_PORT)
      
    if err2 != nil {
      if err2.(net.Bind_Error) == .Address_In_Use {
        continue
      }

      assert(false)
      fmt.println(err2)
    }

    foundPort = true
    discoveryPort = DISCOVERY_PORT
    break
  }

  if foundPort == false {
    fmt.println("ports filled")
    assert(false)
  }

  net.set_blocking(discovery, false)

  network ^= Network {
    discovery = discovery,
    socket = sock,
    myEndpoint = {
      address = addr,
      port = port,
    },
    lobby = {},
    last_broadcast = time.now(),
  }
}

create_lobby :: proc(network: ^Network, name: string) {
  network.lobby = Lobby {
    creatorIdx = 0,
    client_count = 1,
    clients = {},
    name_len = u8(len(name)),
  }

  copy_from_string(network.lobby.name_buf[0:len(name)], name)
  
  network.lobby.clients[0] = Client {
    endpoint = network.myEndpoint,
  }

  broadcast_my_lobby_entry(network)
}

get_client_player_idx :: proc(network: ^Network) -> u8 {
  // in an actual lobby
  assert(network.lobby.client_count != 0)

  for client, i in network.lobby.clients[:network.lobby.client_count] {
    if client.endpoint == network.myEndpoint {
      return u8(i)
    }
  }

  return MAX_PLAYERS
}

broadcast_my_lobby_entry :: proc(network: ^Network) {
  assert(network.lobby.client_count != 0)
  assert(client_is_lobby_master(network))

  now := time.now()
  if time.diff(network.last_broadcast, now) > time.Millisecond * 500 {
    network.last_broadcast = now

    fmt.println("broadcasting")

    payload: [256]u8 

    copy(payload[0:PREFIX_SIZE], LOBBY_ENTRY_PREFIX)
    payload[PREFIX_SIZE] = network.lobby.name_len
    copy(payload[PREFIX_SIZE+1:], network.lobby.name_buf[0:network.lobby.name_len])

    for DISCOVERY_PORT in DISCOVERY_PORTS {
      //TODO
      net.send_udp(network.discovery, payload[0:PREFIX_SIZE+1+network.lobby.name_len], {
        address = network.myEndpoint.address,
        port = DISCOVERY_PORT,
      })
    }
  }
}

request_join_lobby :: proc(network: ^Network, endpoint: net.Endpoint) {
  payload: [PREFIX_SIZE + 19]u8

  copy(payload[:PREFIX_SIZE], LOBBY_JOIN_PREFIX)
  size := encode_endpoint(network.myEndpoint, payload[PREFIX_SIZE:])

  net.send_udp(network.discovery, payload[:PREFIX_SIZE+size], endpoint)
}

fmt_lobby_name :: proc(lobby: ^LobbyEntry) -> string {
  return strings.concatenate({net.endpoint_to_string(lobby.endpoint), " | ", transmute(string)lobby.name_buf[0:lobby.name_len]})
}

client_is_lobby_master :: proc(network: ^Network) -> bool {
  return network.lobby.clients[network.lobby.creatorIdx].endpoint == network.myEndpoint
}

lobby_to_bytes :: proc(lobby: ^Lobby, buf: []u8) -> u16 {
  original_size := len(buf)

  buf := buf
  buf[0] = lobby.name_len
  buf = buf[1:]
  copy_slice(buf[0:lobby.name_len], lobby.name_buf[0:lobby.name_len])
  buf = buf[lobby.name_len:]
  buf[0] = lobby.creatorIdx
  buf[1] = lobby.client_count
  buf = buf[2:]

  for &client in lobby.clients[0:lobby.client_count] {
    buf[0] = client.name_len
    copy_slice(buf[1:client.name_len+1], client.name_buf[0:client.name_len])
    buf = buf[client.name_len+1:]
    size := encode_endpoint(client.endpoint, buf)
    buf = buf[size:]
  }

  return u16(original_size - len(buf))
}

bytes_to_lobby :: proc(payload: []u8) -> (ok: bool, size: u16, lobby: Lobby) {
  offset: u16 = 0
  lobby.name_len = payload[offset]
  offset += 1

  copy(lobby.name_buf[:], payload[offset:u16(lobby.name_len)+offset])
  offset += u16(lobby.name_len)

  lobby.creatorIdx = payload[offset]
  offset += 1 

  lobby.client_count = payload[offset]
  offset += 1 

  for i in 0..<lobby.client_count {
    ok: bool
    clientSize: u16
    ok, clientSize, lobby.clients[i] = bytes_to_client(payload[offset:])

    if !ok {
      fmt.println("parse client failed")
      return false, 0, Lobby{}
    }

    offset += clientSize
  }

  return true, offset, lobby
}

bytes_to_client :: proc(payload: []u8) -> (bool, u16, Client) {
  client: Client

  client.name_len = payload[0]
  copy_slice(client.name_buf[:], payload[1:1+u16(client.name_len)])

  addressSize: u16
  ok: bool
  ok, addressSize, client.endpoint = decode_endpoint(payload[1+u16(client.name_len):])

  if !ok {
    fmt.println("parse client IP failed")
    return false, 0, Client{}
  }

  return true, addressSize+1+u16(client.name_len), client
}

decode_endpoint :: proc(payload: []u8) -> (ok: bool, size: u16, endpoint: net.Endpoint) {
  assert(len(payload) >= 7)

  portNumber := endian.unchecked_get_u16be(payload[0:2])
  endpoint.port = int(portNumber)

  if payload[2] == 4 {
    addressNumber := endian.unchecked_get_u32be(payload[3:7])
    endpoint.address = transmute(net.IP4_Address)addressNumber 
  } else if payload[2] == 16 {
    assert(len(payload) >= 19)

    addressSlice: [16]u8
    copy_slice(addressSlice[:], payload[3:19])
    endpoint.address = transmute(net.IP6_Address)addressSlice
  } else {
    fmt.println("unkown IP format")

    return false, 0, endpoint
  }

  return true, u16(payload[2])+1+2, endpoint
}

encode_endpoint :: proc(endpoint: net.Endpoint, buf: []u8) -> u8 {
  buf := buf
  endian.put_u16(buf[0:2], .Big, u16(endpoint.port))
  buf = buf[2:]

  switch address in endpoint.address {
  case net.IP4_Address:
    buf[0] = 4
    buf = buf[1:]

    endian.put_u32(buf[0:4], .Big, transmute(u32)address)

    return 2 + 1 + 4
  case net.IP6_Address:
    buf[0] = 16
    buf = buf[1:]

    bytes := transmute([16]u8)address
    copy_slice(buf[0:16], bytes[:])
    
    return 2 + 1 + 16
  }

  unreachable()
}

retrieve_lobby_entries :: proc(network: ^Network, endpoint: net.Endpoint, payload: []u8) {
  for lobbyEntry in network.lobbyEntries[0:network.lobbyEntryCount] {
    if lobbyEntry.endpoint == endpoint {
      return
    }
  }

  lobby := &network.lobbyEntries[network.lobbyEntryCount]

  copy(lobby.name_buf[:], payload[1:payload[0]+1])
  lobby.name_len = payload[0]
  lobby.endpoint = endpoint

  network.lobbyEntryCount += 1
}

recieve_discovery_messages :: proc(network: ^Network) {
  buf: [1024]u8
  length, endpoint, err := net.recv_udp(network.discovery, buf[:])

  if err != nil {
    if err != .Would_Block {
      fmt.println(err)
    }
    return
  }

  payload := strings.string_from_ptr(raw_data(buf[:]), PREFIX_SIZE)

  master := client_is_lobby_master(network)

  switch payload {
  case LOBBY_JOIN_PREFIX:
    if master && network.state == .InLobby {
      accept_join_lobby(network, buf[PREFIX_SIZE:])
    }
  case LOBBY_ENTRY_PREFIX:
    if network.state == .Connecting {
      retrieve_lobby_entries(network, endpoint, buf[PREFIX_SIZE:])
    }
  }
}

recieve_messages :: proc(network: ^Network) {
  buf: [1024]u8
  length, endpoint, err := net.recv_udp(network.socket, buf[:])

  if err != nil && err != .Would_Block {
    fmt.println(err)
    return
  }

  payload := strings.string_from_ptr(raw_data(buf[:]), PREFIX_SIZE)

  master := client_is_lobby_master(network)

  switch payload {
  case LOBBY_INFO_PREFIX:
    if !master && (network.state == .WaitingForLobbyInfo || network.state == .InLobby) {
      accept_lobby_info(network, endpoint, buf[PREFIX_SIZE:])
    }
  case LOBBY_STARTGAME_PREFIX:
    if network.state == .InLobby {
      network.state = .Connected
    }
  }
}

accept_lobby_info :: proc(network: ^Network, endpoint: net.Endpoint, payload: []u8){
  ok, size, lobby := bytes_to_lobby(payload)

  if ok {
    network.lobby = lobby
    network.state = .InLobby
  } else {
    fmt.println("parse lobby info failed")
  }
}

accept_join_lobby :: proc(network: ^Network, payload: []u8) {
  ok, size, client_endpoint := decode_endpoint(payload)

  if !ok {
    fmt.println("client decode endpoint failed")
    return
  }

  network.lobby.clients[network.lobby.client_count] = Client {
    endpoint = client_endpoint,
  }
  network.lobby.client_count += 1

  broadcast_my_lobby_info(network)
}

broadcast_my_lobby_info :: proc(network: ^Network) {
  assert(client_is_lobby_master(network))
  buf: [1024]u8

  for client in network.lobby.clients[0:network.lobby.client_count] {
    copy_from_string(buf[:], LOBBY_INFO_PREFIX)

    size := lobby_to_bytes(&network.lobby, buf[PREFIX_SIZE:])

    payload := buf[0:u16(PREFIX_SIZE)+size]

    net.send_udp(network.socket, payload, client.endpoint)
  }
}

broadcast_game_start :: proc(network: ^Network) {
  for client in network.lobby.clients[0:network.lobby.client_count] {
    prefix_buf: [PREFIX_SIZE]u8
    copy(prefix_buf[:], LOBBY_STARTGAME_PREFIX)
    net.send_udp(network.socket, prefix_buf[:], client.endpoint)
  }
}

broadcast_input_state :: proc(network: ^Network) {
  rl.GetMousePosition()
  rl.IsMouseButtonDown(.LEFT)
  rl.IsMouseButtonPressed(.LEFT)
}

update_network :: proc(network: ^Network) {
  switch network.state {
    case .Connected:
    case .WaitingForLobbyInfo:
      recieve_messages(network)

      rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{
        0, 0, 0, 150
      })
    case .InLobby:
      recieve_messages(network)

      rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{
        0, 0, 0, 150
      })
      
      buf: [2]u8
      buf[0] = network.lobby.client_count + '0'
      buf[1] = '\x00'
      rl.DrawText(transmute(cstring)raw_data(buf[:]), 10, 10, 24, rl.WHITE)

      if client_is_lobby_master(network) {
        broadcast_my_lobby_entry(network)
        recieve_discovery_messages(network)

        start := button(&network.ui, rl.Rectangle{
          x = f32(rl.GetScreenWidth())/2 - 75,
          y = f32(rl.GetScreenHeight())/2 - 75,
          width = 150,
          height = 150,
        }, "start", rl.GRAY) 

        if start {
          broadcast_game_start(network)
        }
      }
    case .Connecting:
      recieve_discovery_messages(network)

      rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.Color{
        0, 0, 0, 150
      })

      row_layout(&network.ui, .Up, la.Vector2f32{
        f32(rl.GetScreenWidth())/2 - 75,
        f32(rl.GetScreenHeight())/2 - 75,
      }, 10)

      lobby_count := network.lobbyEntryCount 

      if button(&network.ui, rl.Rectangle{
        width = 150,
        height = 50,
      }, lobby_count > 0 ? fmt_lobby_name(&network.lobbyEntries[0]) : "--", rl.GRAY) {
        request_join_lobby(network, network.lobbyEntries[0].endpoint)
        network.state = .WaitingForLobbyInfo
      }
      
      if button(&network.ui, rl.Rectangle{
        width = 150,
        height = 50,
      }, lobby_count > 1 ? fmt_lobby_name(&network.lobbyEntries[1]) : "--", rl.GRAY) {
        request_join_lobby(network, network.lobbyEntries[1].endpoint)
        network.state = .WaitingForLobbyInfo
      }
      
      if button(&network.ui, rl.Rectangle{
        width = 150,
        height = 50,
      }, lobby_count > 2 ? fmt_lobby_name(&network.lobbyEntries[2]) : "--", rl.GRAY) {
        request_join_lobby(network, network.lobbyEntries[2].endpoint)
        network.state = .WaitingForLobbyInfo
      }
      
      if button(&network.ui, rl.Rectangle{
        width = 150,
        height = 50,
      }, lobby_count > 3 ? fmt_lobby_name(&network.lobbyEntries[3]) : "--", rl.GRAY) {
        request_join_lobby(network, network.lobbyEntries[3].endpoint)
        network.state = .WaitingForLobbyInfo
      }
      
      create_room := button(&network.ui, rl.Rectangle{
        width = 150,
        height = 50,
      }, "create room", rl.GRAY)

      row_layout_end(&network.ui)

      if (create_room) {
        create_lobby(network, "the room")
        network.state = .InLobby
        //start_next_turn(game)
      }
  }
}
