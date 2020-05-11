defmodule Mazurka.Resource do
  @moduledoc """
  TODO write the docs
  """

  alias Mazurka.Resource.Utils

  @doc """
  Initialize a module as a mazurka resource

      defmodule My.Resource do
        use Mazurka.Resource
      end

  TODO document condition, event, input, let, link, mediatype, param, params, and validation
  """
  defmacro __using__(_opts) do
    module = __CALLER__.module
    attr = :__mazurka_resource__
    if !Module.get_attribute(module, attr) do
      Module.put_attribute(module, attr, true)
      Module.register_attribute(module, :operations, accumulate: true)
      quote do
        @before_compile unquote(__MODULE__)

        use Mazurka.Resource.Condition
        use Mazurka.Resource.Event
        use Mazurka.Resource.Input
        use Mazurka.Resource.Let
        use Mazurka.Resource.Link
        use Mazurka.Resource.Mediatype
        use Mazurka.Resource.Option
        use Mazurka.Resource.Param
        use Mazurka.Resource.Validation
        use Mazurka.Resource.Utils.Scope
      end
    end
  end

  defmacro __before_compile__(env) do

    operations = Module.get_attribute(env.module,:operations) |> IO.inspect(label: "operations")
    action_operations = operations |> Enum.map(fn {_type, op} -> op end)

    affordance_operations = operations |> Enum.filter(fn 
        {type, _op} when type in [:param, :input, :let, :condition, :validation] -> true
        _ -> false
    end)
    |> Enum.map(fn {_type, op} -> op end)
    |> Enum.reduce(:ok, fn instruction, parent ->

      # assign a variable with this name
      case instruction do
        {:assign, name} ->
          var = Macro.var(name, __MODULE__)
          quote do
            unquote(var) = unquote(Utils.params)[unquote(name) |> Atom.to_string()]
            unquote(parent)
            # TODO fix unused warning
        end

      # run a function on this variable and reassign its value
        {:run, name, block} ->
          var = Macro.var(name, __MODULE__)
          quote do
            unquote(var) = unquote(block).(unquote(var))
            #IO.puts("run #{unquote(var)}")
        end

        # run a check on a block, and if succeeds, continue else error message
        {:check, block, message} ->
          quote do
            if (unquote(block)) do
              unquote(parent)
            else
              {:error, unquote(message)}
            end
          end
        _ -> parent
     end
    end)

    quote location: :keep do
      @doc """
      Execute a request against the #{inspect(__MODULE__)} resource

          accept = [
            {"application", "json", %{}},
            {"text", "*", %{}}
          ]
          params = %{"user" => "123"}
          input = %{"name" => "Joe"}
          conn = %Plug.Conn{}
          router = My.Router

          #{inspect(__MODULE__)}.action(accept, params, input, conn, router)
      """
      def action(accept, params, input, conn, router \\ nil, opts \\ %{})

      def action(content_types, unquote_splicing(Utils.arguments)) when is_list(content_types) do
        case __mazurka_select_content_type__(content_types) do
          nil ->
            raise Mazurka.UnacceptableContentTypeException, [
              content_type: content_types,
              acceptable: __mazurka_acceptable_content_types__(),
              conn: unquote(Utils.conn)
            ]
          content_type ->
            {response, conn} = action(content_type, unquote_splicing(Utils.arguments))
            {response, content_type, conn}
        end
      end

      @doc """
      Render an affordance for #{inspect(__MODULE__)}

          content_type = {"appliction", "json", %{}}
          params = %{"user" => "123"}
          input = %{"name" => "Fred"}
          conn = %Plug.Conn{}
          router = My.Router

          #{inspect(__MODULE__)}.affordance(content_type, params, input, conn, router)
      """
      def affordance(accept, params, input, conn, router \\ nil, opts \\ %{})

      def affordance(content_types, unquote_splicing(Utils.arguments)) when is_list(content_types) do

        case __mazurka_select_content_type__(content_types) do
          nil ->
            raise Mazurka.UnacceptableContentTypeException, [
              content_type: content_types,
              acceptable: __mazurka_acceptable_content_types__(),
              conn: unquote(Utils.conn)
            ]
          content_type ->
            response = affordance(content_type, unquote_splicing(Utils.arguments))
            {response, content_type}
        end
      end

      def affordance(content_type = {_, _, _}, unquote_splicing(Utils.arguments)) do
        case __mazurka_provide_content_type__(content_type) do
          nil ->
            %Mazurka.Affordance.Unacceptable{resource: __MODULE__,
                                             params: unquote(Utils.params),
                                             input: unquote(Utils.input),
                                             opts: unquote(Utils.opts)}
          mediatype ->
            affordance(mediatype, unquote_splicing(Utils.arguments))
        end
      end


      def affordance(mediatype, unquote_splicing(Utils.arguments)) when is_atom(mediatype) do
        case __mazurka_check_params__(unquote(Utils.params)) do
          {[], []} ->
            unquote(affordance_operations) |> case do
              {:error, _} ->
                %Mazurka.Affordance.Undefined{
                  resource: __MODULE__,
                  mediatype: mediatype,
                  params: unquote(Utils.params),
                  input: unquote(Utils.input),
                  opts: unquote(Utils.opts)
                }
              :ok ->
                __mazurka_match_affordance__(mediatype, unquote_splicing(Utils.arguments), scope)
            end

          {[_ | _] = missing, _} ->
            raise Mazurka.MissingParametersException, params: missing, conn: unquote(Utils.conn())
          _ ->
            %Mazurka.Affordance.Undefined{resource: __MODULE__,
                                          mediatype: mediatype,
                                          params: unquote(Utils.params),
                                          input: unquote(Utils.input),
                                          opts: unquote(Utils.opts)}
        end

      end
    end
  end
end
