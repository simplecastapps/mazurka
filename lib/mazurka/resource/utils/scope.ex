defmodule Mazurka.Resource.Utils.Scope do
  @moduledoc false

  alias Mazurka.Resource.Utils

  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :mazurka_scope, accumulate: true)
      @before_compile unquote(__MODULE__)
    end
  end

  # var Utils.input | Utils.params - place where user supplied inputs and params are stored
  # name :actual name of variable for which result of input, param or let will be stored
  # type :input | :param | nil
  # val_type :validation | :condition | nil
  # block - block of code (if :input or :param then takes an argument)
  #       - returns {:ok, val} or {:error, message} or true or false depending on new or old
  #         style validation / condition
  # error_block - optional for error blocks in old style conditions and validations
  def define(var, name, type, val_type, block, error_block, default, option_fields) do
    block =
      if type in [:input, :param] do
        # passes user input into input or param value into block
        transform_value(var, name, block, type, default, option_fields)
      else
        block
      end

    quote do
      @mazurka_scope {
        # assigned variable name, if any
        unquote(name),
        # :input, :param, nil
        unquote(type),
        # :conditon, :validation, nil
        unquote(val_type),
        # block of code, if any
        unquote(Macro.escape(block)),
        # error block of code, if any
        unquote(Macro.escape(error_block)),
        # default value, if any
        unquote(Macro.escape(default)),
        # option_fields to draw a default value from, if any
        unquote(option_fields)
      }
    end
  end

  def call_validation_func(f, x, name, var_type) do
    case Function.info(f, :arity) do
      {:arity, 1} ->
        f.(x)

      {:arity, 2} ->
        f.(x, field_name: name, var_type: var_type)

      _ ->
        raise "condition / validation function must take between 1 and 2 arguments (value and options)"
    end
  end

  defp transform_value(var, name, nil, _, _default, _option_fields) do
    var_get(var, name)
  end

  defp transform_value(var, name, fun, var_type, default, option_fields) do
    cond do
      option_fields != [] ->
        quote do
          field = unquote(option_fields) |> Enum.reduce_while(:not_found, fn name, accum ->
            case Map.fetch(unquote(Utils.opts()), name) do
              :error -> {:cont, accum}
              {:ok, val} -> {:halt, {:ok, val}}
            end
          end) |> case do
            {:ok, _val} = ok ->
              ok
            :not_found ->
              Mazurka.Resource.Utils.Scope.call_validation_func(
                unquote(fun),
                unquote(var_get(var, name, default)),
                unquote(name),
                unquote(var_type)
              )
          end
       end

      var ->
        quote do
          Mazurka.Resource.Utils.Scope.call_validation_func(
            unquote(fun),
            unquote(var_get(var, name, default)),
            unquote(name),
            unquote(var_type)
          )
        end
      true ->
        quote do
          unquote(fun)
        end
    end
  end

  defp var_get(var, name, default \\ nil) do
    quote do
      case Map.fetch(unquote(var), unquote(name)) do
        :error -> unquote(default)
        {:ok, val} -> val
      end
    end
  end

  defmacro __before_compile__(env) do
    action_variable_map =
      Module.get_attribute(env.module, :mazurka_scope)
      |> Enum.reverse()
      |> scope_binding_names()

    affordance_variable_map =
      Module.get_attribute(env.module, :mazurka_scope)
      |> Enum.reverse()
      |> filter_affordance_relevant()
      |> scope_binding_names()

    #    variable_map = scope_assignments
    action_scope_splice =
      Module.get_attribute(env.module, :mazurka_scope)
      |> Enum.reverse()
      |> scope_splice()

    affordance_scope_splice =
      Module.get_attribute(env.module, :mazurka_scope)
      |> Enum.reverse()
      |> filter_affordance_relevant()
      |> scope_splice()

    quote do
      defp __mazurka_affordance_scope_check__(
             unquote(Utils.mediatype()),
             unquote_splicing(Utils.arguments())
           ) do
        var!(conn) = unquote(Utils.conn())
        _ = var!(conn)

        mazurka_error__ = :no_error
        unquote_splicing(affordance_scope_splice)
        {mazurka_error__, {unquote_splicing(affordance_variable_map)}}
      end

      defp __mazurka_action_scope_check__(
             unquote(Utils.mediatype()),
             unquote_splicing(Utils.arguments())
           ) do
        var!(conn) = unquote(Utils.conn())
        _ = var!(conn)

        #        unquote(Utils.params())
        #        |> Enum.map(fn {k, v} -> {k, v |> to_string()} end)
        #        |> case do
        #          [] -> :ok
        #          xs -> xs |> Logger.metadata()
        #        end

        mazurka_error__ = :no_error
        unquote_splicing(action_scope_splice)
        {mazurka_error__, {unquote_splicing(action_variable_map)}}
      end
    end
  end

  defp scope_splice(scope) do
    scope
    |> Enum.map(fn {name, type, val_type, block, error_block, default, _} ->
      var =
        cond do
          name && type == :input && default == :__mazurka_unspecified ->
            Utils.hidden_var(name)

          name ->
            Macro.var(name, nil)

          true ->
            nil
        end

      run_blocks =
        cond do
          # eg. `input foo`, `input foo, &bar/1` - where the block just runs code, nothing else
          block && !val_type ->
            quote do
              {mazurka_error__, unquote(block)}
            end

          # block that sets a variable on success. `input x  fn x -> {:ok, val} end`
          name && block && !error_block ->
            case block do
              # Prevent match warnings if returning straight up {:ok, ...} or {:error, ...}
              {:ok, code} ->
                quote do
                  {mazurka_error__, unquote(code)}
                end

              {:error, message} ->
                quote do
                  {{unquote(val_type), unquote(message)}, nil}
                end

              _ ->
                quote do
                  case unquote(block) do
                    {:error, message} ->
                      {{unquote(val_type), message}, nil}

                    {:ok, val} ->
                      {mazurka_error__, val}

                    x ->
                      raise "#{unquote(val_type)} on #{unquote(name)} must return {:ok, _} or {:error, _} (got #{inspect(x)})"
                  end
                end
            end

          # block and error block, eg. `condition current_actor, Error.unauthenticated()`
          error_block != :__mazurka_unspecified ->
            quote do
              if unquote(block) do
                {mazurka_error__, nil}
              else
                _ = {{unquote(val_type), unquote(error_block)}, nil}
              end
            end

          # note: backwards compatibility
          # must be a block that has to be evaluated, but with no error message
          true ->
            # condition or validation with no error block, eg. `condition foo != bar`
            quote do
              if !unquote(block) do
                {{unquote(val_type), "unknown_error"}, nil}
              else
                {mazurka_error__, nil}
              end
            end
        end

      # If there is no error yet and we are supposed to run these
      # blocks and assign this var, run them and assign it
      quote do
        # TODO FIXME overwriting variable!
        {mazurka_error__, unquote(var)} =
          if mazurka_error__ != :no_error do
            {mazurka_error__, nil}
          else
            unquote(run_blocks)
          end

        _ = unquote(var)
      end
      |> elem(2)
    end)
    |> Enum.concat()
  end

  # Only scope relevant to affordances
  defp filter_affordance_relevant(scope) do
    scope
    |> Enum.filter(fn {_name, _type, val_type, _block, _error_block, _default, _option_fields} ->
      !val_type or val_type == :condition
    end)
  end

  def filter_by_bindings(scope) do
    scope
    |> Enum.filter(fn
      {nil, _, _, _, _, _, _} -> false
      _ -> true
    end)
  end

  def filter_by(scope, x) when x in [:input, :param, :let] do
    scope
    |> Enum.filter(fn
      {_name, ^x, _, _, _, _, _} -> true
      _ -> false
    end)

  end

  def filter_by_inputs(scope) do
    scope |> filter_by(:input)
  end

  def filter_by_params(scope) do
    scope |> filter_by(:param)
  end

  def filter_by_lets(scope) do
    scope |> filter_by(:let)
  end

  def filter_by_options(scope) do
    scope
    |> Enum.filter(fn
      {_name, _, _, _, _, _, option_fields} when option_fields != [] ->
        true
      _ -> false
    end)
  end


  def scope_binding_names(scope, _opts \\ []) do
    scope
      |> filter_by_bindings()
    |> Enum.map(fn
      # TODO strip inputs
      {name, type, _, _, _, default, _} ->
        if type == :input && default == :__mazurka_unspecified do
          Utils.hidden_var(name)
        else
          Macro.var(name, nil)
        end
    end)
    |> Enum.uniq()
  end


  defmacro dump(scope_type \\ :affordance) do
    # affordances need only condition related variables or unaffiliated variables
    # actions need all of them
    scope =
      Module.get_attribute(__CALLER__.module, :mazurka_scope)
      |> :lists.reverse()
      |> case do
        scope ->
          if scope_type == :affordance do
            scope |> filter_affordance_relevant()
          else
            scope
          end
      end
      |> scope_binding_names()
      |> Enum.map(fn var ->
        {var, quote(do: _ = unquote(var))}
      end)

    # all_vars is all variables in scope
    # all_assigns hides warnings about unused variables
    {all_vars, all_assigns} = scope |> Enum.unzip()
    quote do
      var!(conn) = unquote(Utils.conn())
      _ = var!(conn)
      {unquote_splicing(all_vars)} = unquote(Utils.scope())
      unquote_splicing(all_assigns)
    end
  end
end
