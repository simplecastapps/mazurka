defmodule Mazurka.Resource.Let do
  @moduledoc false

  alias Mazurka.Resource.Utils.Scope

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
    end
  end

  @doc """
  Define an inline variable to be used later in the route.

      let foo do
        123
      end

      let foo = 123

  It can also accept validations or conditions, in which case the supplied
  function must return an `{:ok, val}` or `{:error, reason}` tuple.

      let foobar, validation: fn ->
        if foo == 123 do
          {:ok, 123}
        else
          {:error, "foo wasn't 123"}
        end
      end

  Options:
  * `condition` function with no parameters returning {:ok, val} or {:error, message}
  * `validation` same as condition, but only run in actions, not affordances
  * `default` if this let is a validation, since that isn't run for affordances, this default will be used if it is available, and that will allow this variable to be in scope in affordances and other non validation blocks in the route.
  * `option` if true, use options passed into this route with the same name. If an atom, use options passed in of that name. If list of atoms, use first option passed in that matches. If no matches, do validation / condition as normal with the value that the user passed in.

  There may be at least one validation or condition but not both.
  """
  defmacro let(w, opts \\ []) do
    module = __CALLER__.module

    {w, opts} = case w do
      # support let x = 123
      {:=, _, [{name, _, nil}, []]} -> {name, opts |> Keyword.put(:do, nil)}
      {:=, _, [{name, _, nil}, block]}
         -> {name, opts |> Keyword.put(:do, block)}
      _ -> {w, opts}
    end

    name = field_to_atom(w)

    # option can be true (match current name), an atom, or a list of atoms
    option_fields = opts |> Keyword.get(:option, nil) |> case do
      nil -> []
      true -> [name]
      n when is_atom(n) -> [n]
      ns when is_list(ns) -> ns
      _ -> []
    end

    # We have to use :__maz_uns because it is perfectly valid to pass
    # eg. `default: nil`, or `let foo = nil`
    default =
      opts
      |> Keyword.fetch(:default)
      |> case do
        :error -> :__mazurka_unspecified
        {:ok, v} -> v
      end

    validation = fn_to_block(Keyword.get(opts, :validation, :__mazurka_unspecified))

    # `let foo do 1232 end` is equivalent to `let foo, condition: {:ok, 1232}`
    condition_block = opts |> Keyword.fetch(:do) |> case do
      :error -> :__mazurka_unspecified
      {:ok, res} -> quote do {:ok, unquote(res)} end
    end
    condition = fn_to_block(Keyword.get(opts, :condition, condition_block))

    {val_type, block} = cond do
      validation != :__mazurka_unspecified && condition != :__mazurka_unspecified ->
        raise "You can't specify both a validation and condition block in the same let"
      validation == :__mazurka_unspecified && condition == :__mazurka_unspecified ->
        raise "You must specify at least one of a validation or condition in this let"
      validation != :__mazurka_unspecified -> {:validation, validation}
      true -> {:condition, condition}
    end

    Scope.define(module, nil, name, :let, val_type, block, nil, default, option_fields)
  end

  # a let do with extra options, aka, for example `let foo, option: true do end`
  defmacro let(w, opts, [do: block]) do
    opts = opts |> Keyword.put(:do, block)
    quote do
      let(unquote(w), unquote(opts))
    end
  end

  # let foo = ... -> :foo
  defp field_to_atom({name, _, nil}) when is_atom(name) do
    name
  end
  defp field_to_atom(name) when is_atom(name) do
    name
  end

  # `let foo, condition: fn -> {:ok, foobar} end`
  # is equivalent to
  # `let foo, condition: {:ok, foobar}
  defp fn_to_block({:fn, _, [{:->, _, [[], block]}]}) do
    block
  end

  # let foo, condition: &Validations.is_integer/0
  defp fn_to_block({:&, _, _} = block) do
    # let foo do 2 end is equivalent to
    quote do (unquote(block)).() end
  end

  defp fn_to_block({:fn, _, _}) do
    raise "Invalid block format. Type h #{__MODULE__}.let/2"
  end

  defp fn_to_block(block) do
    block
  end

  defmacro all(type \\ :atom) do
    # keyword list from variable atom to stored variable name
    all_options =
      __CALLER__.module
      |> Module.get_attribute(:mazurka_scope)
      |> Enum.reverse()
      |> Mazurka.Resource.Utils.Scope.filter_by_lets()
      |> Enum.map(fn
        {_var, name, :input, _, _, _, default, _} ->
          if default == :__mazurka_unspecified do
            []
          else
            [{name, Macro.var(name, nil)}]
          end
          {_var, name, _, _, _, _, _default, _} -> [{name, Macro.var(name, nil)}]
      end)
      |> Enum.concat()
     # Enum.uniq_by first duplicate key is winner, we want last.
     |> Map.new()
     |> Enum.to_list()

    if type == :atom do
      quote do
        unquote({:%{}, [], all_options})
      end
    else
      quote do
        unquote({:%{}, [], all_options |> Enum.map(fn {k, v} -> {to_string(k), v} end)})
      end
    end
  end
end
