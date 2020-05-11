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

    operations = Module.get_attribute(env.module,:operations)
    scope_splice = operations
       |> Enum.filter(fn
         {_type, {:assign, _assign_type, _name}} -> true
         {_type, {:run, _name, _}} -> true
         _ -> false
       end)
       |> Enum.map(fn
         {_type, {:assign, _assign_type, name}} -> name
         {_type, {:run, name, _}} -> name
       end)
       |> Enum.uniq
       |> Enum.reduce(quote do %{} end, fn name, accum ->
           quote do
            unquote(accum) |> Map.put(unquote(name), unquote(Macro.var(name, nil)))
          end
        end)

    affordance_operations = operations |> Enum.filter(fn
        {type, _op} when type in [:param, :input, :let, :condition, :validation] -> true
        _ -> false
    end)

    [affordance_op_splice, action_op_splice] = [affordance_operations, operations]
    |> Enum.map(fn operations ->
      operations
        |> Enum.map(fn {_type, op} -> op end)
        |> Enum.reduce(quote do {:ok, unquote(scope_splice)} end, fn instruction, parent ->

      # assign a variable with this name from runtime (inputs / params)
      case instruction do
        {:assign, type, name} ->

          # I still don't understand how scope assigns work, but this seems to be correct
          mod = case type do
            :input -> Mazurka.Resource.Input
            :param -> Mazurka.Resource.Param
          end

          var = Macro.var(name, nil)
          quote do
            unquote(var) = unquote(mod).get(unquote(name) |> Atom.to_string())
            unquote(parent)
            # TODO fix unused warning
        end

        # run a function and assign it to this variable (lets)
        {:run, name, block} ->
            var = Macro.var(name, nil)
            quote do
              unquote(var) = unquote(block)
              unquote(parent)
              #IO.puts("run self #{unquote(var)}")
            end
          # run a function on this variable with itself as argument and reassign its value
          # (inputs / params with functions)
          {:run_self, name, block} ->
            var = Macro.var(name, nil)
            quote do
              unquote(var) = unquote(block).(unquote(var))
              unquote(parent)
              #IO.puts("run #{unquote(var)}")
          end

          # run a check on a block of code, and if succeeds, continue else error message
          # (validation, condition)
          {:check, block, message} ->
            quote do
              if (unquote(block)) do
                unquote(parent)
              else
                {:error, unquote(message)}
              end
            end
          err -> raise "This should not be reachable #{(inspect(err))}"
       end
      end)
    end)

    quote location: :keep do

      # param input, some_fn/1
      # validation true && param1, "fail1"
      # param input2, some_fn2/1
      # condition param1 && param2, "fail2"
      # let foo = if !param1 do raise "unreachable error" else some_fn3(param1) end

      # expands to a function like

      #    param1 = "123"
      #    param1 = some_fn.(param1)
      #
      #    if true && param1 do
      #      param2 = "asdf"
      #      param2 = some_fn2.(param2)
      #      if param1 && param2 do
      #        foo = if !param1 do raise "unreachable error" else some_fn3(param1) end
      #        {:ok,
      #          %{}
      #          |> Map.put(:param1, param1)
      #          |> Map.put(:param2, param2)
      #          |> Map.put(:foo, foo)
      #        }
      #      else
      #        {:error, "fail2"}
      #      end
      #    else
      #      {:error, "fail1"}
      #    end

      # The returned map is all the variables that have been set if no checks
      # failed.  Note that everything is evaluated in order, if a check
      # fails nothing after that failure will have been executed.

     defp __mazurka_evaluate_affordance__(unquote_splicing(Utils.arguments)) do
       unquote(affordance_op_splice)
     end

     defp __mazurka_evaluate_action__(unquote_splicing(Utils.arguments)) do
       unquote(action_op_splice)
     end

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
    end
  end
end
