defmodule Mazurka.Resource.Option do
  @moduledoc false

  alias Mazurka.Resource.Utils
  # Option.get gets raw input, unmodified by lets, etc, but can be used before
  # action / affordance
  use Utils.Global, var: :opts, type: :atom, style: :raw

  defmacro __using__(_) do
    quote do
      require unquote(__MODULE__)
      # alias unquote(__MODULE__)
    end
  end

  @doc """
  Define an option that may have been passed by a previous route and send
  this option into future routes.

      input input1, option: true, condition: ...
      input input1, option: :otherinput, condition: ...
      input input1, option: [:trythis, :thenthis, :input1], condition: ...
      param param1, option: true, condition: ...
      let let1, option: true do
        2
      end

  """
  defmacro all(type \\ :atom) do
    # keyword list from variable atom to stored variable name
    all_options =
      __CALLER__.module
      |> Module.get_attribute(:mazurka_scope)
      |> Enum.reverse()
      |> Mazurka.Resource.Utils.Scope.filter_by_options()
      |> Mazurka.Resource.Utils.Scope.filter_by_bindings()
      |> Enum.map(fn {_var, name, _, _, _, _, _default, _} ->
        {name, Macro.var(name, nil)}
      end)

    if type == :atom do
      {:%{}, [], all_options}
    else
      all_options = all_options |> Enum.map(fn {k, v} -> {to_string(k), v} end)
      {:%{}, [], all_options}
    end
  end

  defmacro all_bindings(type \\ :atom) do
    # keyword list from variable atom to stored variable name

    all_bindings =
      __CALLER__.module
      |> Module.get_attribute(:mazurka_scope)
      |> Enum.reverse()
      |> Mazurka.Resource.Utils.Scope.filter_by_bindings()
      |> Enum.map(fn
          {_var, name, :input, _, _, _, default, _} ->
        if default == :__mazurka_unspecified do
          {name, {:input, Utils.hidden_var(name)}}
        else
          {name, {:input, Macro.var(name, nil)}}
        end

        {_var, name, input_type, _, _, _, _default, _} ->
          {name, {input_type, Macro.var(name, nil)}}
      end)
      |> Map.new()
      |> Enum.to_list()

    if type == :atom do
      quote do
        supplied_inputs = unquote(Utils.input()) |> Map.keys()

        unquote(all_bindings) |> Enum.filter(fn
          {k, {:input, v}} -> k in supplied_inputs
          _ -> true
        end)
        |> Enum.map(fn {k, {_, v}} -> {k, v} end) |> Map.new()
      end
    else
      quote do
        supplied_inputs = unquote(Utils.input()) |> Map.keys()

        unquote(all_bindings) |> Enum.filter(fn
          {k, {:input, v}} -> k in supplied_inputs
          _ -> true
        end)
        |> Enum.map(fn {k, {_, v}} -> {k |> to_string(), v} end) |> Map.new()
      end
    end
  end
end
