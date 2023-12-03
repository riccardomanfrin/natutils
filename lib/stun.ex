defmodule STUN do
  @moduledoc """
  STUN Client implementation module
  """

  require Record
  Record.extract_all(from_lib: "stun/include/stun.hrl")

  Record.defrecord(
    :stun,
    :stun,
    Record.extract(:stun, from_lib: "stun/include/stun.hrl")
  )

  @google_default_stun_server_name ~c"stun.l.google.com"

  @doc """
  Perform a STUN request against Google STUN server, and retrieve router WAN IP address and mapped port.

  It's than not obvious if you can use the outbound opened port from a different address / port (hole punching).

  You have to verify if you have

   - `full-cone` NAT [Good],
   - `address-restricted-cone` NAT [Good] (you must send the packet to the addr of the peer you want to receive from),
   - `port-restricted-cone` [Good] (you must send a packet to the addr AND port of the peer you want to receive from),
   - `simmetric` NAT (meaning you can't use hole punching).
  """
  @spec get_wan_public_ip_addr_port(
          local_net_ip_addr :: :inet.ip4_address(),
          local_port :: 0..65535
        ) :: {wan_public_ip_addr :: :inet.ip4_address(), wan_external_port :: 0..65535}

  def get_wan_public_ip_addr_port(local_net_ip_addr \\ Utils.local_net_ip_addr(), local_port \\ 0) do
    {:ok, sock} = :gen_udp.open(local_port, [:binary, {:ip, local_net_ip_addr}, {:active, false}])
    {:ok, {_ip, _port}} = :inet.sockname(sock)
    binding_req = :stun_codec.encode(bind_req())
    # https://gist.github.com/zziuni/3741933
    # stun.l.google.com -> 74.125.128.127
    :gen_udp.send(sock, google_stun_server_ip_addr(), 19302, binding_req)
    {:ok, {_, _, resp}} = :gen_udp.recv(sock, 0)
    {:ok, resp_dec} = :stun_codec.decode(resp, :datagram)
    stun("XOR-MAPPED-ADDRESS": wan_public_ip_addr_port) = resp_dec
    :gen_udp.close(sock)
    wan_public_ip_addr_port
  end

  defp bind_req(),
    do: stun(method: 0x1, class: :request, trid: 41_809_861_624_941_132_369_239_212_033)

  defp google_stun_server_ip_addr() do
    {:ok, {_, _, _, :inet, 4, [addr | _rest]}} =
      :inet_res.gethostbyname(@google_default_stun_server_name)

    addr
  end
end
