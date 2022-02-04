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

  def eval_default(default, required, var_name, var_type, val_type) do
    cond do
      default != :__mazurka_unspecified -> quote do {:ok, unquote(default)} end

      required != :__mazurka_unspecified -> quote do
        {:error, ((unquote(required)).(field_name: unquote(var_name), var_type: unquote(var_type), validation_type: unquote(val_type)))}
      end

      true -> quote do {:ok, :__mazurka_unspecified} end
    end
  end

  # used for input / param validations, aka fn x, opts -> ... end
  def apply(f, val, opts) do
    case Function.info(f, :arity) do
      # backwards compatibility, input foo, fn x -> ... end
      {:arity, 1} ->
        f.(val)
      {:arity, 2} ->
        f.(val, opts)
    end
  end

  def fetch_var(var, var_name, variable, apply, on_error) do
    quote do
      case Map.fetch(unquote(var), unquote(var_name)) do
        # If var is not fetchable and default is ever :__mazurka_unspecified
        # then that is a serious bug.
        :error -> unquote(on_error)
          # function has to return either {:ok, _} or {:error, _}
        {:ok, unquote(variable)} -> unquote(apply)
      end
    end
  end

  defp fetch_option(option_fields, variable, on_success, on_error) do
    case option_fields || [] do
      [] -> on_error
      [field] ->
        quote do
          case Map.fetch(unquote(Utils.opts()), unquote(field)) do
            :error -> unquote(on_error)
            {:ok, unquote(variable)} ->
              unquote(on_success)
          end
        end
      option_fields ->
        quote do
          unquote(option_fields) |> Enum.reduce_while(:not_found, fn name, accum ->
            case Map.fetch(unquote(Utils.opts()), name) do
              :error -> {:cont, accum}
              {:ok, val} -> {:halt, {:ok, val}}
            end
          end) |> case do
            {:ok, unquote(variable)} ->
              unquote(on_success)
            :not_found ->
              unquote(on_error)
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
  def define(module, var, name, type, val_type, block, error_block, default_or_required, option_fields) do
    # due to compilation timing issues, we can't guarantee a call to this
    # will happen before other modules will start calling define.
    if !Module.has_attribute?(module, :mazurka_scope) do
      Module.register_attribute(module, :mazurka_scope, accumulate: true)
    end
    Module.put_attribute(module, :mazurka_scope, {
        # Utils.input, Utils.params, Utils.options
        var,
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
        # if input is not supplied, default value or an error block
        default_or_required,
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

    action_scope_splice =
      Module.get_attribute(env.module, :mazurka_scope)
      |> Enum.reverse()
      |> scope_splice(:action)

    affordance_scope_splice =
      Module.get_attribute(env.module, :mazurka_scope)
      |> Enum.reverse()
      |> filter_affordance_relevant()
      |> scope_splice(:affordance)

    quote do
      alias Mazurka.Resource.Utils.Scope, as: MSC
      defp __mazurka_affordance_scope_check__(
             unquote(Utils.mediatype()),
             unquote_splicing(Utils.arguments())
           ) do
        var!(conn) = unquote(Utils.conn())
        _ = var!(conn)

        mazurka_error__ = :no_error
        unquote(affordance_scope_splice)
        {mazurka_error__, {unquote_splicing(affordance_variable_map)}}
      end

      defp __mazurka_action_scope_check__(
             unquote(Utils.mediatype()),
             unquote_splicing(Utils.arguments())
           ) do
        var!(conn) = unquote(Utils.conn())
        _ = var!(conn)

        mazurka_error__ = :no_error
        unquote(action_scope_splice)
        {mazurka_error__, {unquote_splicing(action_variable_map)}}
      end
    end
  end

  defp scope_splice(scope, scope_type) when scope_type in [:action, :affordance] do
    res = scope
    |> Enum.map(fn {var_type, name, type, val_type, block, error_block, default_or_required, option_fields} ->

      {default, required} = default_or_required |> case do
        {:default, d} -> {d, :__mazurka_unspecified}
        {:required, r} -> {:__mazurka_unspecified, r}
        _ -> {:__mazurka_unspecified, :__mazurka_unspecified}
      end

      var =
        cond do
          # inputs are optional, and if there is no default value, their binding should be hidden from use
          # as a variable in any inputs, params, lets, or blocks because they may not have a defined value.
          name && type == :input && default == :__mazurka_unspecified && required == :__mazurka_unspecified ->
            Utils.hidden_var(name)

          name ->
            Macro.var(name, nil)

          true ->
            nil
        end

      block =
        case type do
          # inputs and params take an argument
          _ when val_type == :validation and scope_type == :affordance ->
            # affordances don't execute validations, so if there is a default,
            # use it, unless there is an option, in which case use that.
            variable = Macro.unique_var(:val, nil)
            # defaults can be evaluated on the validation affordance level, but required can never can be
            default = eval_default(default, :__mazurka_unspecified, name, type, val_type)
            not_found = quote do unquote(default) end
            found = quote do {:ok, unquote(variable)} end
            fetch_option(option_fields, variable, found, not_found)

          _ when type in [:input, :param] ->

            # inputs and params blocks take an argument, so we have to apply it.
            variable = Macro.unique_var(:val, nil)
            default = eval_default(default, required, name, type, val_type)     #  {:ok, _} | {:error, _}

            apply = quote do MSC.apply(unquote(block), unquote(variable), field_name: unquote(name), var_type: unquote(type), validation_type: unquote(val_type)) end
            block = fetch_var(var_type, name, variable, apply, default)         # Map.fetch!(INPUT, variable) |> case do {:ok, apply}; {:error, default} end
            block = fetch_option(option_fields, variable, apply, block)         # Map.fetch!(OPTION, variable) |> case do {:ok, apply}; {:error, block}
            quote do unquote(block) end
          _ ->
            # let blocks should just be executed, unless an option applies
            variable = Macro.unique_var(:val, nil)
            found = quote do {:ok, unquote(variable)} end       # we found an option, use it
            fetch_option(option_fields, variable, found, block)
        end

      # if an option was passed in and this field accepts it, just replace the block with it
      # entirely

      run_block =
        cond do
          # eg. `input foo`, `input foo, &bar/1` - where the block just runs code, nothing else
          block && !val_type ->
            quote do
              {mazurka_error__, unquote(block)}
            end

          # block that sets a variable on success. `input x  fn x -> {:ok, val} end`
          name && block && !error_block ->
            case block do
              # Prevent match warnings if returning plain {:ok, ...} or {:error, ...}
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
                {{unquote(val_type), unquote(block |> Macro.to_string())}, nil}
              else
                {mazurka_error__, nil}
              end
            end
        end

      # If there is no error yet and we are supposed to run these
      # blocks and assign this var, run them and assign it
      quote do
        {mazurka_error__, unquote(var)} =
          if mazurka_error__ != :no_error do
            {mazurka_error__, nil}
          else
            unquote(run_block)
          end
        _ = unquote(var)
      end

    end)

    quote do
      unquote_splicing(res)
    end
  end

  # Only scope relevant to affordances
  defp filter_affordance_relevant(scope) do
    scope
    |> Enum.filter(fn {_var, _name, _type, val_type, _block, _error_block, default, _option_fields} ->
      val_type == :condition || (val_type == :validation && default != :__mazurka_unspecified)
    end)
  end

  def filter_by_bindings(scope) do
    scope
    |> Enum.filter(fn
      {_var, nil, _, _, _, _, _, _} -> false
      _ -> true
    end)
  end

  def filter_by(scope, x) when x in [:input, :param, :let] do
    scope
    |> Enum.filter(fn
      {_var, _name, ^x, _, _, _, _, _} -> true
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
      {_var, _name, _, _, _, _, _, option_fields} when option_fields != [] ->
        true
      _ -> false
    end)
  end


  def scope_binding_names(scope, _opts \\ []) do
    scope
    |> filter_by_bindings()
    |> Enum.map(fn
      {_var, name, type, _, _, _, default_or_required, _} ->
        if type == :input && default_or_required == :__mazurka_unspecified do
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
