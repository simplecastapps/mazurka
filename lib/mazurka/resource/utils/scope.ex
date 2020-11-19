defmodule Mazurka.Resource.Utils.Scope do
  @moduledoc false

  alias Mazurka.Resource.Utils

  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :mazurka_scope, accumulate: true)
      @before_compile unquote(__MODULE__)
    end
  end

  def define(var, name, block, type \\ :binary, class \\ nil)
  def define(var, {name, _, _}, block, type, class) when is_atom(name) do
    define(var, name, block, type, class)
  end
  def define(var, name, block, :binary, class) when is_atom(name) do
    bin_name = to_string(name)
    block = transform_value(var, bin_name, block)
    compile_assignment(name, block, class)
  end
  def define(var, name, block, :atom, class) when is_atom(name) do
    block = transform_value(var, name, block)
    compile_assignment(name, block, class)
  end

  def check(check_type, block, message) do
    compile_check(check_type, block, message)
  end

  defp transform_value(var, name, []) do
    var_get(var, name)
  end
  defp transform_value(var, name, fun) do
    quote do
      (unquote(fun)).(unquote(var_get(var, name)))
    end
  end

  defp var_get(var, name) do
    quote do
      unquote(var)[unquote(name)]
    end
  end

  defmacro __before_compile__(env) do
    scope_assignments = Module.get_attribute(env.module, :mazurka_scope) |> assignments()

    values = scope_assignments |> Enum.flat_map(fn({name, code}) ->
      var = Macro.var(name, nil)
      quote do
        unquote(var) = unquote(code)
        _ = unquote(var)
      end |> elem(2)
    end)
    map = scope_assignments |> Enum.map(fn({n, _}) -> Macro.var(n, nil) end)

    # ---
    scope = Module.get_attribute(env.module, :mazurka_scope) |> Enum.reverse
    scope_splice = scope |> Enum.map(fn
      {:assignment, _class, {name, code}} ->
        var = Macro.var(name, nil)
        quote do
        unquote(var) = case mazurka_error__ do
          :no_error -> unquote(code)
            _ -> nil
          end
           _ = unquote(var)
        end |> elem(2)

      {:check, {check_type, condition, error_code}} ->

        # This avoids a "this check/guard will always yield the same result"
        # warning during compilation when making use of validations
        tcheck = if check_type == :validation do
            quote do: resource_type == :affordance
          else
            quote do: false
          end
        quote do
          mazurka_error__ = 
            if (mazurka_error__ != :no_error || unquote(tcheck)) do
              mazurka_error__
            else
              if (unquote(condition)) do
                mazurka_error__
              else
                 code = unquote(error_code)
                 _ = {unquote(check_type), code}
              end
            end
        _ = mazurka_error__
        end |> elem(2)
    end) |> Enum.concat

    quote do
      defp __mazurka_scope_check__(resource_type, unquote(Utils.mediatype), unquote_splicing(Utils.arguments)) do
        var!(conn) = unquote(Utils.conn)
        _ = var!(conn)
        mazurka_error__ = :no_error
        unquote_splicing(scope_splice)
        {mazurka_error__, {unquote_splicing(map)}}
      end

      defp __mazurka_scope__(unquote(Utils.mediatype), unquote_splicing(Utils.arguments)) do
        var!(conn) = unquote(Utils.conn)
        _ = var!(conn)
        unquote_splicing(values)
        {unquote_splicing(map)}
      end
    end
  end

  def compile_assignment(name, block, class \\ nil) do
    quote do
      @mazurka_scope {:assignment, unquote(class), {unquote(name), unquote(Macro.escape(block))}}
    end
  end

  def compile_check(check_type, block, message) do
    quote do
      @mazurka_scope {:check, {unquote(check_type), unquote(Macro.escape(block)), unquote(Macro.escape(message))}}
    end
  end

  defp assignments(scope, class \\ :all) do
    scope |> :lists.reverse() |> Enum.filter(fn
      {:assignment, _class, _x} when class == :all -> true
      {:assignment, ^class, _x} -> true
      _ -> false
    end) |> Enum.map(fn {:assignment, _class, x} -> x end)
  end

  defmacro dump_as_ob(mod) do
    scope = Module.get_attribute(mod, :mazurka_scope) |> assignments

    kvs = scope |> Enum.map(fn {n, _v} -> n end) |> Enum.uniq |> Enum.map(fn k ->
      {k, Macro.var(k, nil)}
    end)

    # create a map of %{var_name as atom -> var name}
    {:%{}, [], kvs}
  end

  defmacro dump() do
    scope = Module.get_attribute(__CALLER__.module, :mazurka_scope) |> assignments
    inputs = Module.get_attribute(__CALLER__.module, :mazurka_scope) |> assignments(:input)
    params = Module.get_attribute(__CALLER__.module, :mazurka_scope) |> assignments(:param)

    vars = Enum.map(scope, fn({n, _}) -> Macro.var(n, nil) end)
    assigns = Enum.map(scope, fn({n, _}) -> quote(do: _ = unquote(Macro.var(n, nil))) end)

    quote do
      var!(conn) = unquote(Utils.conn)
      _ = var!(conn)
      {unquote_splicing(vars)} = unquote(Utils.scope)
      unquote_splicing(assigns)
      {var!(mazurka_all_input), var!(mazurka_all_params)} =
        {
          unquote(inputs) |> Enum.filter(fn {_k, v} -> v end) |> Map.new(),
          unquote(params) |> Map.new()
        }
      _ = var!(mazurka_all_params)
      _ = var!(mazurka_all_input)
    end
  end
end
