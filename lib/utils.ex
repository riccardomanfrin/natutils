defmodule Utils do
  @moduledoc """
  Supplies some convenience function to deal with p2p connectivity in ipv4 network.
  """

  @on_load :init

  @doc """
  Loads routing table nif based on Netlink socket communication.
  """
  def init do
    :ok = :erlang.load_nif("#{:code.priv_dir(:natutils)}/route_table", 0)
  end

  @doc """
  Returns the equivalent of running "ip r" on a conventional Linux OS.
  """
  def route_table(), do: exit(:nif_not_loaded)

  @doc """
  Returns the router address by inspecting the route table and looking up
  the default route "via" content.

  The default route and the router gateway are assumed to be unique in the routing table.
  In other words the networking has to be plain simple: no multihoming.
  """
  def router_ip_addr() do
    routes = route_table()

    [router_ip_addr] =
      for %{mask: 0, net: {0, 0, 0, 0}} = r <- routes do
        r.via
      end

    router_ip_addr
  end

  @doc """
  Returns the public WAN ip address of the router (by having a STUN exchange with google servers).
  """
  def public_ip_addr() do
    # {:ok, addr} = HTTPoison.get!("https://api.ipify.org").body
    # |> String.to_charlist()
    # |> :inet.parse_address()
    # addr
    {ip, _port} = STUN.get_wan_public_ip_addr_port()
    ip
  end

  @doc """
  Infers local network address in the router network, by connecting to the
  router and inspecting the socket local IP address.
  """
  def local_net_ip_addr(router_ip_addr \\ router_ip_addr()) do
    {:ok, sock} = :gen_udp.open(0)
    :gen_udp.connect(sock, router_ip_addr, 6666)
    {:ok, {local_net_ip_address, _}} = :inet.sockname(sock)
    :gen_udp.close(sock)
    local_net_ip_address
  end
end
