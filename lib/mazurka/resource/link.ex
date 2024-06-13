defmodule Mazurka.Resource.Link do
  @moduledoc false

  alias Mazurka.Resource.Utils

  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :mazurka_links, accumulate: true)
      import unquote(__MODULE__)
      alias unquote(__MODULE__)
      require Logger
      @before_compile unquote(__MODULE__)
    end
  end

  @doc """
  Link to another resource
  """

  defmacro link_to(resource, params \\ nil, input \\ nil, fragment \\ nil, opts \\ nil) do

    formatted_params = format_params(params)
    formatted_input = format_params(input)
    opts = format_opts(opts)
    version = Module.get_attribute(__CALLER__.module, :mazurka_version)
    Module.put_attribute(__CALLER__.module, :mazurka_links, resource)

    opt_bindings = if version <= 1 do
        # In version one of mazurka, we send all bindings into links because we had no
        # mechanism to specify which ones should go
        quote do: Mazurka.Resource.Option.all_bindings()
      else
        # In version two, we only send options that were specified in elements, eg.
        # input option: true ..., let current_actor, option: :logged_in_user do ...
        quote do: Mazurka.Resource.Option.all()
    end

    quote do
      conn = var!(conn)
      router = unquote(Utils.router)
      resource = unquote(resource)

      source = %{resource: __MODULE__,
                 file: __ENV__.file,
                 line: __ENV__.line,
                 params: unquote(Utils.params),
                 input: unquote(Utils.input),
                 mediatype: unquote(Utils.mediatype),
                 opts: unquote(Utils.opts)}

      module = Mazurka.Router.resolve_resource(router, resource, source, conn)

      # new opts created in this route (via eg. option: true)
      # + inputs explicitly passed in (so that they won't be stripped)
      # + params explicitly passed in (so they won't be stripped)
      # + opts explicitly passed into link_to
      opts = unquote(opt_bindings)
        |> Map.merge(unquote(format_opts(input)))
        |> Map.merge(unquote(format_opts(params)))
        |> Map.merge(unquote(opts))


      warn = Map.get(opts, :warn)

      case module do
        nil when warn != false ->
          file_line = Exception.format_file_line(__ENV__.file, __ENV__.line)
          Logger.warning("#{file_line} resource #{inspect(resource)} not found")
          nil
        nil ->
          nil
        _ ->
          module.affordance(
            unquote(Utils.mediatype),
            Mazurka.Router.format_params(router, unquote(formatted_params), source, conn),
            Mazurka.Router.format_params(router, unquote(formatted_input), source, conn),
            conn,
            router,
            Map.put(opts, :fragment, unquote(fragment))
          )
      end
    end
  end

  @doc """
  Transition to another resource
  """

  defmacro transition_to(resource, params \\ nil, input \\ nil, opts \\ nil) do
    params = format_params(params)
    input = format_params(input)
    opts = format_opts(opts)

    quote do
      conn = var!(conn)

      target = Mazurka.Resource.Link.resolve(
        unquote(resource),
        unquote(params),
        unquote(input),
        conn,
        unquote(Utils.router),
        unquote(opts)
      )

      var!(conn) = Mazurka.Conn.transition(conn, target)

      target
    end
  end

  @doc """
  Invalidate another resource
  """

  defmacro invalidates(resource, params \\ nil, input \\ nil, opts \\ nil) do
    params = format_params(params)
    input = format_params(input)
    opts = format_opts(opts)

    quote do
      conn = var!(conn)

      target = Mazurka.Resource.Link.resolve(
        unquote(resource),
        unquote(params),
        unquote(input),
        conn,
        unquote(Utils.router),
        unquote(opts)
      )

      var!(conn) = Mazurka.Conn.invalidate(conn, target)

      target
    end
  end

  def format_params(nil) do
    {:%{}, [], []}
  end
  def format_params({:%{}, meta, items}) do
    {:%{}, meta, Enum.map(items, fn({name, value}) ->
      {to_string(name), value}
    end)}
  end
  def format_params(items) when is_list(items) do
    {:%{}, [], Enum.map(items, fn({name, value}) ->
      {to_string(name), value}
    end)}
  end
  def format_params(other) do
    quote do
      Enum.reduce(unquote(other), %{}, fn({name, value}, acc) ->
        Map.put(acc, to_string(name), value)
      end)
    end
  end

  defp format_opts(opts) when opts in [nil, []] do
    {:%{}, [], []}
  end
  defp format_opts({:%{}, _meta, _items} = map) do
    map
  end
  defp format_opts(items) when is_list(items) do
    {:%{}, [], items}
  end
  defp format_opts(other) do
    quote do
      Enum.into(unquote(other), %{})
    end
  end

  defmacro resolve(resource, params, input, conn, router, opts) do
    current_params = Utils.params
    current_input = Utils.input
    current_mediatype = Utils.mediatype
    current_opts = Utils.opts

    quote location: :keep, bind_quoted: binding() do
      case router do
        nil ->
          raise Mazurka.MissingRouterException, resource: resource, params: params, input: input, conn: conn, opts: opts
        router ->
          source = %{resource: __MODULE__,
                     file: __ENV__.file,
                     line: __ENV__.line,
                     params: current_params,
                     input: current_input,
                     mediatype: current_mediatype,
                     opts: current_opts}

          params = Mazurka.Router.format_params(router, params, source, conn)
            |> Enum.map(fn {k, v} -> {k |> to_string(), v} end) |> Map.new()
          input  = Mazurka.Router.format_params(router, input, source, conn)
            |> Enum.map(fn {k, v} -> {k |> to_string(), v} end) |> Map.new()

          affordance = %Mazurka.Affordance{resource: resource,
                                           params: params,
                                           input: input,
                                           opts: opts}

          Mazurka.Router.resolve(router, affordance, source, conn)
      end
    end
  end

  defmacro rel_self do
    quote do
      unquote(__MODULE__).resolve(
        __MODULE__,
        unquote(Utils.params),
        unquote(Utils.input),
        var!(conn),
        unquote(Utils.router),
        unquote(Utils.opts)
      )
    end
  end

  defmacro __before_compile__(_) do
    quote unquote: false do
      links = @mazurka_links
      |> Enum.filter(fn
        ({:__aliases__, _, _}) -> true
        (name) when is_binary(name) or is_atom(name) -> true
        (_) -> false
      end)
      |> Enum.uniq()
      |> Enum.sort()
      def links do
        unquote(links)
      end
    end
  end
end
