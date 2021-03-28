defmodule ReqTest do
  use ExUnit.Case, async: true

  setup do
    bypass = Bypass.open()
    [bypass: bypass, url: "http://localhost:#{bypass.port}"]
  end

  test "high-level API", c do
    Bypass.expect(c.bypass, "GET", "/ok", fn conn ->
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    assert Req.get!(c.url <> "/ok").body == "ok"
  end

  ## Low-level API

  test "low-level API", c do
    Bypass.expect(c.bypass, "GET", "/ok", fn conn ->
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    state = Req.build(:get, c.url <> "/ok")
    assert {:ok, %{status: 200, body: "ok"}} = Req.run(state)
  end

  test "simple request step", c do
    Bypass.expect(c.bypass, "GET", "/ok", fn conn ->
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    state =
      Req.build(:get, c.url <> "/not-found")
      |> Req.add_request_steps([
        fn request ->
          %{request | path: "/ok"}
        end
      ])

    assert {:ok, %{status: 200, body: "ok"}} = Req.run(state)
  end

  test "request step returns response", c do
    state =
      Req.build(:get, c.url <> "/ok")
      |> Req.add_request_steps([
        fn _request ->
          %Finch.Response{status: 200, body: "from cache"}
        end
      ])
      |> Req.add_response_steps([
        fn response ->
          update_in(response.body, &(&1 <> " - updated"))
        end
      ])

    assert {:ok, %{status: 200, body: "from cache - updated"}} = Req.run(state)
  end

  test "request step returns exception", c do
    state =
      Req.build(:get, c.url <> "/ok")
      |> Req.add_request_steps([
        fn _request ->
          RuntimeError.exception("oops")
        end
      ])
      |> Req.add_error_steps([
        fn exception ->
          update_in(exception.message, &(&1 <> " - updated"))
        end
      ])

    assert {:error, %RuntimeError{message: "oops - updated"}} = Req.run(state)
  end

  test "request step halts with response", c do
    state =
      Req.build(:get, c.url <> "/ok")
      |> Req.add_request_steps([
        fn _request ->
          {:halt, %Finch.Response{status: 200, body: "from cache"}}
        end
      ])
      |> Req.add_response_steps([
        &unreachable/1
      ])
      |> Req.add_error_steps([
        &unreachable/1
      ])

    assert {:ok, %{status: 200, body: "from cache"}} = Req.run(state)
  end

  test "request step halts with exception", c do
    state =
      Req.build(:get, c.url <> "/ok")
      |> Req.add_request_steps([
        fn _request ->
          {:halt, RuntimeError.exception("oops")}
        end
      ])
      |> Req.add_response_steps([
        &unreachable/1
      ])
      |> Req.add_error_steps([
        &unreachable/1
      ])

    assert {:error, %RuntimeError{message: "oops"}} = Req.run(state)
  end

  test "simple response step", c do
    Bypass.expect(c.bypass, "GET", "/ok", fn conn ->
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    state =
      Req.build(:get, c.url <> "/ok")
      |> Req.add_response_steps([
        fn response ->
          update_in(response.body, &(&1 <> " - updated"))
        end
      ])

    assert {:ok, %{status: 200, body: "ok - updated"}} = Req.run(state)
  end

  test "response step returns exception", c do
    Bypass.expect(c.bypass, "GET", "/ok", fn conn ->
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    state =
      Req.build(:get, c.url <> "/ok")
      |> Req.add_response_steps([
        fn response ->
          assert response.body == "ok"
          RuntimeError.exception("oops")
        end
      ])
      |> Req.add_error_steps([
        fn exception ->
          update_in(exception.message, &(&1 <> " - updated"))
        end
      ])

    assert {:error, %RuntimeError{message: "oops - updated"}} = Req.run(state)
  end

  test "response step halts with response", c do
    Bypass.expect(c.bypass, "GET", "/ok", fn conn ->
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    state =
      Req.build(:get, c.url <> "/ok")
      |> Req.add_response_steps([
        fn response ->
          {:halt, update_in(response.body, &(&1 <> " - updated"))}
        end,
        &unreachable/1
      ])
      |> Req.add_error_steps([
        &unreachable/1
      ])

    assert {:ok, %{status: 200, body: "ok - updated"}} = Req.run(state)
  end

  test "response step halts with exception", c do
    Bypass.expect(c.bypass, "GET", "/ok", fn conn ->
      Plug.Conn.send_resp(conn, 200, "ok")
    end)

    state =
      Req.build(:get, c.url <> "/ok")
      |> Req.add_response_steps([
        fn _response ->
          {:halt, RuntimeError.exception("oops")}
        end,
        &unreachable/1
      ])
      |> Req.add_error_steps([
        &unreachable/1
      ])

    assert {:error, %RuntimeError{message: "oops"}} = Req.run(state)
  end

  test "simple error step", c do
    Bypass.down(c.bypass)

    state =
      Req.build(:get, c.url <> "/ok")
      |> Req.add_error_steps([
        fn exception ->
          assert exception.reason == :econnrefused
          RuntimeError.exception("oops")
        end
      ])

    assert {:error, %RuntimeError{message: "oops"}} = Req.run(state)
  end

  test "error step returns response", c do
    Bypass.down(c.bypass)

    state =
      Req.build(:get, c.url <> "/ok")
      |> Req.add_response_steps([
        fn response ->
          update_in(response.body, &(&1 <> " - updated"))
        end
      ])
      |> Req.add_error_steps([
        fn exception ->
          assert exception.reason == :econnrefused
          %Finch.Response{status: 200, body: "ok"}
        end,
        &unreachable/1
      ])

    assert {:ok, %{status: 200, body: "ok - updated"}} = Req.run(state)
  end

  test "error step halts with response", c do
    Bypass.down(c.bypass)

    state =
      Req.build(:get, c.url <> "/ok")
      |> Req.add_response_steps([
        &unreachable/1
      ])
      |> Req.add_error_steps([
        fn exception ->
          assert exception.reason == :econnrefused
          {:halt, %Finch.Response{status: 200, body: "ok"}}
        end,
        &unreachable/1
      ])

    assert {:ok, %{status: 200, body: "ok"}} = Req.run(state)
  end

  ## Request steps

  test "default_headers/1" do
    state =
      Req.build(:get, "http://localhost")
      |> Req.add_request_steps([
        &Req.default_headers/1,
        fn request ->
          {_, user_agent} = List.keyfind(request.headers, "user-agent", 0)
          %Finch.Response{status: 200, body: user_agent}
        end
      ])

    assert {:ok, %{status: 200, body: "req/0.1.0-dev"}} = Req.run(state)
  end

  ## Response steps

  test "decode/1", c do
    Bypass.expect(c.bypass, "GET", "/json", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode_to_iodata!(%{"a" => 1}))
    end)

    state =
      Req.build(:get, c.url <> "/json")
      |> Req.add_response_steps([
        &Req.decode/1
      ])

    assert {:ok, %{status: 200, body: %{"a" => 1}}} = Req.run(state)
  end

  ## Error steps

  test "retry: eventually successful", c do
    {:ok, _} = Agent.start_link(fn -> 0 end, name: :counter)

    Bypass.expect(c.bypass, "GET", "/retry", fn conn ->
      if Agent.get_and_update(:counter, &{&1, &1 + 1}) < 2 do
        Plug.Conn.send_resp(conn, 500, "oops")
      else
        Plug.Conn.send_resp(conn, 200, "ok")
      end
    end)

    state =
      Req.build(:get, c.url <> "/retry")
      |> Req.add_response_steps([
        &Req.retry/2,
        fn response ->
          update_in(response.body, &(&1 <> " - updated"))
        end
      ])

    assert {:ok, %{status: 200, body: "ok - updated"}} = Req.run(state)
    assert Agent.get(:counter, & &1) == 3
  end

  test "retry: always failing", c do
    pid = self()

    Bypass.expect(c.bypass, "GET", "/retry", fn conn ->
      send(pid, :ping)
      Plug.Conn.send_resp(conn, 500, "oops")
    end)

    state =
      Req.build(:get, c.url <> "/retry")
      |> Req.add_response_steps([
        &Req.retry/2,
        fn response ->
          update_in(response.body, &(&1 <> " - updated"))
        end
      ])

    assert {:ok, %{status: 500, body: "oops - updated"}} = Req.run(state)
    assert_received :ping
    assert_received :ping
    assert_received :ping
    refute_received _
  end

  ## Helpers

  defp unreachable(_response) do
    raise "unreachable"
  end
end
