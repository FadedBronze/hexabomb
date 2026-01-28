package main

import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:time"
import "core:encoding/endian"

MAX_CLIENTS :: 4
MAX_LOBBIES :: 4
DISCOVERY_PORTS := [3]int{4000, 4001, 4002}
MAX_NAME_CHARS :: 32

LOBBY_INFO_PREFIX ::  "HXBLBINF_"
LOBBY_JOIN_PREFIX ::  "HXBLJOIN_"
LOBBY_ENTRY_PREFIX :: "HXBENTRY_"
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
  clients: [MAX_NAME_CHARS]Client,
}

LobbyEntry :: struct {
  endpoint: net.Endpoint,
  name_buf: [MAX_NAME_CHARS]u8,
  name_len: u8,
}

Network :: struct {
  last_broadcast: time.Time,

  lobbyEntries: [MAX_LOBBIES]LobbyEntry,
  lobbyEntryCount: u8,

  discovery: net.UDP_Socket,
  socket: net.UDP_Socket,
  lobby: Lobby,
  myEndpoint: net.Endpoint,
}

init_network :: proc(network: ^Network) -> bool {
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

  if err != nil {
    fmt.println(err)
    return false
  }
  
  discovery: net.UDP_Socket 
  foundPort: bool = false
  discoveryPort: int

  for DISCOVERY_PORT in DISCOVERY_PORTS[:] {
    err2: net.Network_Error 
    discovery, err2 = net.make_bound_udp_socket(addr, DISCOVERY_PORT)

    if err2 != nil {
      if err2 == net.Bind_Error.Address_In_Use {
        continue
      }

      fmt.println(err2)
      return false
    }

    foundPort = true
    discoveryPort = DISCOVERY_PORT
    break
  }

  fmt.println(discoveryPort, discovery)

  if foundPort == false {
    fmt.println("ports filled")
    return false
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

  return true
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
  payload := LOBBY_JOIN_PREFIX
  net.send_udp(network.discovery, transmute([]byte)payload, endpoint)
}

recieve_messages :: proc(network: ^Network) {
  buf: [1024]u8
  length, endpoint, err := net.recv_udp(network.socket, buf[:])

  if err != nil && err != .Would_Block {
    fmt.println(err)
    return
  }

  payload := strings.string_from_ptr(raw_data(buf[:]), PREFIX_SIZE)

  master := !client_is_lobby_master(network)
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

recieve_discovery_messages :: proc(network: ^Network, gameState: GameState) {
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
  case LOBBY_INFO_PREFIX:
    if !master && gameState == .WaitingForLobbyInfo {
      accept_lobby_info(network, endpoint, buf[PREFIX_SIZE:])
    }
  case LOBBY_JOIN_PREFIX:
    if master && gameState == .InLobby {
      accept_join_lobby(network, endpoint)
    }
  case LOBBY_ENTRY_PREFIX:
    if gameState == .Connecting {
      retrieve_lobby_entries(network, endpoint, buf[PREFIX_SIZE:])
    }
  }
}

accept_lobby_info :: proc(network: ^Network, endpoint: net.Endpoint, payload: []u8){
  fmt.println("accepted", payload)
}

accept_join_lobby :: proc(network: ^Network, endpoint: net.Endpoint) {
  network.lobby.clients[network.lobby.client_count] = Client {
    endpoint = endpoint,
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

    net.send_udp(network.discovery, payload, client.endpoint)
  }
}
