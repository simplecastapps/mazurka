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

  defp eval_default(default, required, var_name, var_type, val_type) do
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

  defp fetch_var(var, var_name, variable, apply, on_error) do
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
      |> scope_filter_by(bindings: true)
      |> scope_as_binding_splice(&scope_is_hidden/1)

    affordance_variable_map =
      Module.get_attribute(env.module, :mazurka_scope)
      |> Enum.reverse()
      |> scope_filter_by(bindings: true, affordance_relevant: true)
      |> scope_as_binding_splice(&scope_is_hidden/1)

    action_scope_splice =
      Module.get_attribute(env.module, :mazurka_scope)
      |> Enum.reverse()
      |> scope_splice(:action)

    affordance_scope_splice =
      Module.get_attribute(env.module, :mazurka_scope)
      |> Enum.reverse()
      |> scope_filter_by(affordance_relevant: true)
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
        {mazurka_error__, unquote(affordance_variable_map)}
      end

      defp __mazurka_action_scope_check__(
             unquote(Utils.mediatype()),
             unquote_splicing(Utils.arguments())
           ) do
        var!(conn) = unquote(Utils.conn())
        _ = var!(conn)

        mazurka_error__ = :no_error
        unquote(action_scope_splice)
        {mazurka_error__, unquote(action_variable_map)}
      end
    end
  end

  # P: param     I: input      L: let
  # C: condition V: validation
  # r: required  d: default
  #
  # H: FROM variable should unusable in (aka HIDDEN from) TO block
  # U: Any hidden variables should be brought into scope for this case
  #
  # example:
  #   PC -> param foo1, condition: ...
  #   IC -> input foo2, condition: ...
  #   IVd -> input foo3, default: :foo, validation: ...
  #   IV -> input foo4, validation: inspect(foo3) # <- fine, foo3 defaults to :foo if not specified
  #   IV -> input foo5, validation: inspect(foo4) # <- error referencing optional input with no default or required
  #   IV -> input foo6, validation: inspect(foo1) # <- fine, foo2 is a param so it is always there
  #
  #                     FROM
  #           condition               validation
  #          PC IC ICd ICr LC        IV IVd IVr  LV  LVd
  # T     C    H                     H      H   H
  # O
  #       V    H                     H      HU  HU
  #
  #  should be hidden if
  #    HIDDEN == FROM((IC && !d && !r) || (V && !d)) (anything that might not be globally applicable due to optionality)
  #
  #  hidden variables should be brought into scope if
  #    UNHIDDEN == TO:V && FROM:(V && (r || L)) (if it is required and on validation level, it should be available in validation level blocks)
  #
  #
  #  F: filter out (in filter_affordance_relevant)
  #  U: unhide (in scope_binding_names)
  #                     FROM
  #           condition              validation
  #          PC IC ICd ICr LC       IV IVd IVr LV  LVd
  #
  #      AFF                        F      F    F
  #
  #      ACT                               U    U
  #
  #  hidden variables should be unhidden from affordance if
  #    AFFORD == never
  #
  #  hidden variables should be unhidden for action if
  #    ACTION == IVr || LV (params are required, and we know it has been validated) (inputs that are required must have been validated)

  # TODO remove Param Validation, it makes no sense and is likely a bug
  defp scope_splice(scope, scope_type) when scope_type in [:action, :affordance] do
    res = scope
    |> Enum.scan({nil, []}, fn {var_type, name, type, val_type, block, error_block, default_or_required, option_fields} = scope, {_, hidden_val_vars} ->

      {default, required} = default_or_required |> case do
        {:default, d} -> {d, :__mazurka_unspecified}
        {:required, r} -> {:__mazurka_unspecified, r}
        _ -> {:__mazurka_unspecified, :__mazurka_unspecified}
      end

      {var, is_hidden} =
        cond do
          # inputs are optional, and if there is no default value, their binding should be hidden from use
          # as a variable in any inputs, params, lets, or blocks because they may not have a defined value.
          # required should be hidden from anything not in the validation level
          # FROM((IC && !d && !r) || (V && !d))
          scope |> scope_is_hidden() ->
            {Utils.hidden_var(name), true}

          name ->
            {Macro.var(name, nil), false}

          true ->
            {nil, false}
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

      hvars =
        # UNHIDDEN == TO:V && FROM:(V && (r || L))
        case val_type == :validation && hidden_val_vars || [] do
          [] -> quote do end
          _ ->
          #FROM:(V && (r || L))
          hidden_val_vars = hidden_val_vars |> Enum.filter(fn {_name, type, val_type, _default, required} ->
            (val_type == :validation && (required != :__mazurka_unspecified || type == :let))
            end)

            vars = hidden_val_vars |> Enum.map(fn {name, _, _, _, _} ->
              quote do unquote(Macro.var(name, nil)) = unquote(Utils.hidden_var(name)) end
            end)
            var_assigns = hidden_val_vars |> Enum.map(fn {name, _, _, _, _} ->
              quote do _ = unquote(Macro.var(name, nil)) end
            end)
            quote do
              unquote_splicing(vars)
              unquote_splicing(var_assigns)
            end
        end

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
                  unquote(hvars)
                  {mazurka_error__, unquote(code)}
                end

              {:error, message} ->
                quote do
                  {{unquote(val_type), unquote(message)}, nil}
                end

              _ ->
                quote do
                  unquote(hvars)
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
              unquote(hvars)
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
              unquote(hvars)
              if !unquote(block) do
                {{unquote(val_type), unquote(block |> Macro.to_string())}, nil}
              else
                {mazurka_error__, nil}
              end
            end
        end

      # If there is no error yet and we are supposed to run these
      # blocks and assign this var, run them and assign it
      res = quote do
        {mazurka_error__, unquote(var)} =
          if mazurka_error__ != :no_error do
            {mazurka_error__, nil}
          else
            unquote(run_block)
          end
        _ = unquote(var)
      end

      # these are variables that need to be hidden from the condition level scope.
      hidden_val_vars = if is_hidden do
        [{name, type, val_type, default, required} | hidden_val_vars] |> Enum.uniq()
      else
        hidden_val_vars
      end

      {res, hidden_val_vars }
    end) |> Enum.map(fn x -> x |> elem(0) end)

    quote do
      unquote_splicing(res)
    end
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


  def scope_as_binding_splice(scope, via) do
    vars = scope |> Enum.filter(&scope_is_variable/1) |> Enum.uniq() |> Enum.map(fn x ->
      x |> scope_binding(via)
    end)

    quote do {unquote_splicing(vars)} end
  end

  def scope_as_name_binding_list(scope, via) do
    vars = scope |> Enum.filter(&scope_is_variable/1) |> Enum.uniq()
    vars |> Enum.map(fn scope ->
      binding = scope |> scope_binding(via)
      name = scope |> scope_name()
      {name, binding}
    end)
  end
  def scope_as_name_type_binding_list(scope, via) do
    vars = scope |> Enum.filter(&scope_is_variable/1) |> Enum.uniq()
    vars |> Enum.map(fn scope ->
      binding = scope |> scope_binding(via)
      name = scope |> scope_name()
      type = scope |> scope_type()
      {name, {type, binding}}
    end)
  end

  def scope_as_name_binding_splice(scope, via) do
    vars = scope |> scope_as_name_binding_list(via)
    quote do unquote(vars) end
  end

  def scope_as_variable_splice(scope) do
    vars = scope |> Enum.filter(&scope_is_variable/1) |> Enum.uniq() |> Enum.map(fn scope ->
      Macro.var(scope |> scope_name(), nil)
    end)

    quote do {unquote_splicing(vars)} end
  end

  def scope_filter_by(scope, opts \\ []) do
    bindings = opts[:bindings] || nil
    inputs = opts[:inputs] || nil
    params = opts[:params] || nil
    lets = opts[:lets] || nil
    affordance_relevant = opts[:affordance_relevant] || nil
    action_unhidden = opts[:action_unhidden] || nil
    scope |> Enum.filter(fn scope ->
      {_var_type, _name, type, _val_type, _block, _error_block, _default_or_required, _option_fields} = scope
      (is_nil(bindings) || (bindings == scope |> scope_is_variable)) &&
      (is_nil(params) || (params == (type == :param))) &&
      (is_nil(inputs) || (inputs == (type == :input))) &&
      (is_nil(lets) || (lets == (type == :let))) &&
      (is_nil(affordance_relevant) || (affordance_relevant == scope |> scope_is_affordance_relevant())) &&
      (is_nil(action_unhidden) || (action_unhidden == scope |> scope_is_unhidden_in_action()))
    end)
  end

  def scope_is_variable(scope) do
    # it is a variable if it has a name
    scope |> elem(1) != nil
  end

  # hidden scope is any named variable that isn't always globally available in
  # every context
  def scope_is_hidden(scope) do
    {_var, name, type, val_type, _, _, default_or_required, _} = scope

    {default, required} = default_or_required |> case do
      {:default, d} -> {d, :__mazurka_unspecified}
      {:required, r} -> {:__mazurka_unspecified, r}
      _ -> {:__mazurka_unspecified, :__mazurka_unspecified}
    end


    # HIDDEN == FROM((IC && !d && !r) || (V && !d))
    name && (
      (type == :input && val_type == :condition && default == :__mazurka_unspecified && required == :__mazurka_unspecified) ||
        (val_type == :validation && default == :__mazurka_unspecified)
    )
  end

  # hidden scope variables that are visible in action blocks
  def scope_is_unhidden_in_action(scope) do
    {_var, _name, type, val_type, _, _, default_or_required, _} = scope
    hidden = scope |> scope_is_hidden()

    # UNHIDDEN ACTION == IVr || LV
    is_required = default_or_required |> case do
      {:required, _} -> true
      _ -> false
    end

    hidden && (
      val_type == :validation && (is_required || type == :let)
    )
  end

  # hidden scope variables that are visible in validation blocks
  def scope_is_unhidden_in_validation(scope) do
    {_var, _name, type, val_type, _, _, default_or_required, _} = scope
    hidden = scope |> scope_is_hidden()

    is_required = default_or_required |> case do
      {:required, _} -> true
      _ -> false
    end

    hidden && (
      val_type == :validation && (is_required || type == :let)
    )
  end

  def scope_is_affordance_relevant(scope) do
    {_var, _name, _type, val_type, _block, _error_block, default_or_required, _option_fields} = scope

    has_default = default_or_required |> case do
      {:default, _} -> true
      _ -> false
    end

    val_type == :condition || (val_type == :validation && has_default)
  end


  def scope_binding(scope, via) do
    name = scope |> scope_name()
    if scope |> via.() do
      Utils.hidden_var(name)
    else
      Macro.var(name, nil)
    end
  end

  def scope_name(scope) do
    scope |> elem(1)
  end
  def scope_type(scope) do
    scope |> elem(2)
  end

  defmacro dump(scope_type \\ :affordance) do
    # affordances need only condition related variables or unaffiliated variables
    # actions need all of them
    #

    scope =
      Module.get_attribute(__CALLER__.module, :mazurka_scope)
      |> :lists.reverse()
      |> scope_filter_by(
        bindings: true,
        affordance_relevant: scope_type == :affordance
      )

    # These have to be hidden as if we were not in the action because
    # Input.all() will assume such a hidden status when called
    all_vars = scope |> scope_as_binding_splice(&scope_is_hidden/1)
    {unhidden_vars,unhidden_hidden_vars} = if scope_type == :action do
      scope = scope |> scope_filter_by(action_unhidden: true)
      unhidden_vars = scope |> scope_as_binding_splice(fn scope ->
        scope_is_hidden(scope) && !scope_is_unhidden_in_action(scope)
      end)
      unhidden_hidden_vars = scope |> scope_as_binding_splice(&scope_is_hidden/1)
      {unhidden_vars, unhidden_hidden_vars}
    else
      {nil, nil}
    end

    # all_vars is all variables in scope
    # all_assigns hides warnings about unused variables
    # some vars are hidden by default and need to be unhidden in action blocks
    quote do
      var!(conn) = unquote(Utils.conn())
      _ = var!(conn)
      unquote(all_vars) = unquote(Utils.scope())
      _ = unquote(all_vars)
      unquote(unhidden_vars) = unquote(unhidden_hidden_vars)
      _ = unquote(unhidden_vars)
    end
  end
end
