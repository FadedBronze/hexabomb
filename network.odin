package main

import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:time"

MAX_CLIENTS :: 4
MAX_LOBBIES :: 4
DISCOVERY_PORTS := [3]int{4000, 4001, 4002}

LOCAL_IP := net.IP4_Address{127, 0, 0, 1}
BROADCAST_IP := LOCAL_IP

Client :: struct {
  endpoint: net.Endpoint,
}

Lobby :: struct {
  name: string,
  client_count: u8,
  creatorIdx: u8,
  clients: [MAX_CLIENTS]Client,
}

LobbyEntry :: struct {
  endpoint: net.Endpoint,
  name_buf: [32]u8,
  name: string,
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
    name = name,
  }
  
  network.lobby.clients[0] = Client {
    endpoint = network.myEndpoint,
  }

  broadcast_my_lobby_name(network)
}

broadcast_my_lobby_name :: proc(network: ^Network) {
  assert(network.lobby.client_count != 0)
  assert(client_is_lobby_master(network))

  now := time.now()
  if time.diff(network.last_broadcast, now) > time.Millisecond * 500 {
    network.last_broadcast = now

    fmt.println("broadcasting")

    payload := strings.concatenate({"HEXB_LOBBY_", network.lobby.name})

    for DISCOVERY_PORT in DISCOVERY_PORTS {
      //TODO
      net.send_udp(network.socket, transmute([]byte)payload, {
        address = network.myEndpoint.address,
        port = DISCOVERY_PORT,
      })
    }
  }
}

request_join_lobby :: proc(network: ^Network, endpoint: net.Endpoint) {
  payload := "HEXB_JOIN"
  net.send_udp(network.socket, transmute([]byte)payload, endpoint)
}

fmt_lobby_name :: proc(lobby: ^LobbyEntry) -> string {
  buf: [32]u8
  str := strconv.itoa(buf[:], lobby.endpoint.port)
  return strings.concatenate({net.address_to_string(lobby.endpoint.address), ":", str, " | ", lobby.name})
}

client_is_lobby_master :: proc(network: ^Network) -> bool {
  return network.lobby.clients[network.lobby.creatorIdx].endpoint == network.myEndpoint
}

//broadcast_my_lobby_info :: proc(network: ^Network) {
//  lobby := &network.lobbies[network.myLobbyId-1]
//
//  for client in lobby.clients[0:lobby.client_count] {
//    payload := lobby^
//
//    net.send_udp(network.socket, transmute([]byte)payload, client.endpoint)
//  }
//}

retrieve_lobby_entries :: proc(network: ^Network) {
  temp_buf: [32]u8 

  if length, remote, err := net.recv_udp(network.discovery, temp_buf[:]); err == nil {
    fmt.println("recieving")

    for lobbyEntry in network.lobbyEntries[0:network.lobbyEntryCount] {
      if lobbyEntry.endpoint == remote {
        return
      }
    }

    lobby := &network.lobbyEntries[network.lobbyEntryCount]
    lobby.name_buf = temp_buf

    payload := strings.string_from_ptr(raw_data(lobby.name_buf[:]), length)
    name := strings.trim_prefix(payload, "HEXB_LOBBY_")

    lobby.name = name
    lobby.endpoint = remote

    network.lobbyEntryCount += 1
  } else if err != .Would_Block {
    fmt.println(err)
  }
}
