defmodule Mazurka.Resource.Let do
  @moduledoc false

  alias Mazurka.Resource.Utils.Scope

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
    end
  end

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

    Scope.define(module, nil, name, :let, val_type, block, nil, nil, option_fields)
  end

  # let foo = ... -> :foo
  defp field_to_atom({name, _, nil}) when is_atom(name) do
    name
  end
  defp field_to_atom(name) when is_atom(name) do
    name
  end

  # `let foo, condition: fn -> if x {:ok, 123} else {:error, "message"} end end`
  # is equivalent to
  # `let foo, condition: if {:ok, 123} else {:error, "message"} end`
  defp fn_to_block({:fn, _, [{:->, _, [[], block]}]}) do
    block
  end

  # let foo, condition: &Validations.is_integer/0
  defp fn_to_block({:&, _, _} = block) do
    # let foo do 2 end is equivalent to
    quote do (unquote(block)).() end
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
        {name, :input, _, _, _, default, _} ->
          if default == :__mazurka_unspecified do
            []
          else
            [{name, Macro.var(name, nil)}]
          end
          {name, _, _, _, _, _default, _} -> [{name, Macro.var(name, nil)}]
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
