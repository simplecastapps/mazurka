defmodule Mazurka.Resource.Utils.Scope do
  @moduledoc false

  alias Mazurka.Resource.Utils

  defmacro __using__(_) do
    quote do
      if !Module.has_attribute?(__MODULE__, :mazurka_scope) do
        Module.register_attribute(__MODULE__, :mazurka_scope, accumulate: true)
      end
      @before_compile unquote(__MODULE__)
    end
  end

  def apply_argument(var, if_exists, default, var_name, var_type, val_type) do

    block =
      quote do
        case Function.info(unquote(if_exists), :arity) do
          # backwards compatibility, input foo, fn x -> ... end
          {:arity, 1} ->
            unquote(if_exists).(val)
          {:arity, 2} ->
            unquote(if_exists).(val, field_name: unquote(var_name), var_type: unquote(var_type), validation_type: unquote(val_type))
        end
      end

    quote do
      case Map.fetch(unquote(var), unquote(var_name)) do
        :error -> {:ok, unquote(default)}
          # function has to return either {:ok, _} or {:error, _}
        {:ok, val} -> unquote(block)
      end
    end
  end

  defp fetch_option(option_fields, fun) do
    case option_fields do
      [] -> fun
      [field] ->
        quote do
          case Map.fetch(unquote(Utils.opts()), unquote(field)) do
            :error -> unquote(fun)
            {:ok, _val} = ok -> ok
          end
        end
      _ ->
        quote do
          unquote(option_fields) |> Enum.reduce_while(:not_found, fn name, accum ->
            case Map.fetch(unquote(Utils.opts()), name) do
              :error -> {:cont, accum}
              {:ok, val} -> {:halt, {:ok, val}}
            end
          end) |> case do
            {:ok, _val} = ok ->
              ok
            :not_found ->
              unquote(fun)
          end
       end
    end
  end


  # var Utils.input | Utils.params - place where user supplied inputs and params are stored
  # name :actual name of variable for which result of input, param or let will be stored
  # type :input | :param | :let | nil
  # val_type :validation | :condition | nil
  # block - block of code (if :input or :param then code takes an argument)
  #       - returns {:ok, val} or {:error, message} or true or false depending on new or old
  #         style validation / condition
  # error_block - optional for error blocks in old style conditions and validations
  def define(module, var, name, type, val_type, block, error_block, default, option_fields) do
    block =
      case type do
        _ when type in [:input, :param] ->

          # passes user input into input or param value into block
          # TODO this really needs to be done upon rendering the scope rather than at
          # definition time to help optimize away code that will never be hit.
          fun = apply_argument(var, block, default, name, type, val_type)

          fetch_option(option_fields, fun)

        :let ->
          fetch_option(option_fields, block)

        _ -> block
      end

    # due to compilation timing issues, we can't guarantee a call to this
    # will happen before other modules will start calling define.
    if !Module.has_attribute?(module, :mazurka_scope) do
      Module.register_attribute(module, :mazurka_scope, accumulate: true)
    end
    Module.put_attribute(module, :mazurka_scope, {
        # assigned variable name, if any
        name,
        # :input, :param, :let
        type,
        # :condition, :validation, nil
        val_type,
        # block of code, if any
        block,
        # error block of code, if any
        error_block,
        # default value, if any
        default,
        # option_fields to draw a default value from, if any
        option_fields
      })
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
    |> Enum.filter(fn {_name, _type, val_type, _block, _error_block, default, _option_fields} ->
      !val_type or val_type == :condition or
      # allow validated bindings if they have a default
      (val_type == :validation && default != :__mazurka_unspecified)
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
