defmodule PCP do
  @moduledoc """
  Port Control Protocol v2 Client (PCPv2, rfc6887)  implementation to control routers NAT port mapping

  The code has been tested on my Fritzbox, on my network, on my planet..

  - Fritzbox 7490 does support the PCPv2 protocol [RFC-6887](https://datatracker.ietf.org/doc/html/rfc6887).
    Reference: [avm doc](https://en.avm.de/service/knowledge-base/dok/FRITZ-Box-7590-AX/894_Setting-up-automatic-port-sharing/)


  It would be interesting to build a bit of stats around this. Feel free to report about supporting routers.
  """

  @pcp_default_server_port 5351
  @pcp_default_client_port 5350

  @map_opcode 1
  @version 2
  @reserved 0
  @lifetime 3600
  @tcp 6

  @version 2
  @success 0
  @not_authorized_or_refused 2
  @type_response 1
  @response @type_response * 128 + @map_opcode

  @type short_integer :: 0..65535

  @doc """
  Open a port map in the router Network Address Translation (NAT) table:

      {local address, inner_port} <-> {wan_ip_addr, outer_mapped_port}

  The function sends a PCP `MAP` [IANA OpCode](https://www.iana.org/assignments/pcp-parameters/pcp-parameters.xhtml) message to the router to open an external port and map it into an internal local
  port and local address.

  Local address is inferred from local router address (it's assumed to be in the same network).

  Router address is inferred from the default route or can be explicitly provided.

  WAN address is inferred from a STUN message exchanged with Google, or it can be explicitly provided.

  The Function returns the assigned external IP address and port and the lifetime of the mapping in seconds.

  Example:

      iex> PCP.open_port_map(5555,5555)
      {:ok, {{200,1,2,3}, 5555, 120}}

  Note: The assigned external port and IP can differ from the ones specified in the request, for example
  in the case where the external port is already assigned to another ongoing communication. Make
  sure to always inspect the result to know which port has been assigned to you.
  """
  @spec open_port_map(
          inner_port :: short_integer(),
          outer_mapped_port :: short_integer(),
          router_ip_addr :: :inet.ip4_address(),
          wan_ip_addr :: :inet.ip4_address()
        ) ::
          {:ok,
           {external_assigned_address :: :inet.ip4_address(),
            external_assigned_port :: short_integer(), lifetime :: integer()}}
          | {:error, :not_authorized_or_refused}
  def open_port_map(
        inner_port,
        outer_mapped_port,
        router_ip_addr \\ Utils.router_ip_addr(),
        wan_ip_addr \\ Utils.public_ip_addr()
      ) do
    {:ok, sock} = :gen_udp.open(@pcp_default_client_port, [:binary, {:active, false}])

    pcp_pkt = [
      @version,
      Bitwise.band(@map_opcode, 0b1111111),
      @reserved,
      @reserved,
      <<@lifetime::32-integer>>,
      router_ip_addr
      |> Utils.local_net_ip_addr()
      |> addr6(),
      :crypto.strong_rand_bytes(12),
      @tcp,
      @reserved,
      @reserved,
      @reserved,
      <<inner_port::16-integer>>,
      <<outer_mapped_port::16-integer>>,
      addr6(wan_ip_addr)
    ]

    :ok = :gen_udp.send(sock, router_ip_addr, @pcp_default_server_port, pcp_pkt)
    {:ok, {_ip, _port, data}} = :gen_udp.recv(sock, 0)

    <<@version, @response, @reserved, result, lifetime::32-integer, _epoch::32-integer,
      _reserved1::binary-size(12), _nonce::binary-size(12), _proto::binary-size(1),
      _reserved2::binary-size(3), _internal_port::16-integer, assigned_external_port::16-integer,
      assigned_external_ip_addr::binary>> =
      data

    :ok = :gen_udp.close(sock)

    case result do
      @success -> {:ok, {addr4(assigned_external_ip_addr), assigned_external_port, lifetime}}
      @not_authorized_or_refused -> {:error, :not_authorized_or_refused}
    end
  end

  defp addr6(v4), do: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF | Tuple.to_list(v4)]

  defp addr4(<<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xFF, v4::binary>>),
    do: List.to_tuple(:binary.bin_to_list(v4))
end
