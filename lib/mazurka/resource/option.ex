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
      |> Enum.map(fn {name, _, _, _, _, _default, _} ->
        [name, Macro.var(name, nil)]
      end)
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

  defmacro all_bindings(type \\ :atom) do
    # keyword list from variable atom to stored variable name
    all_bindings =
      __CALLER__.module
      |> Module.get_attribute(:mazurka_scope)
      |> Enum.reverse()
      |> Mazurka.Resource.Utils.Scope.filter_by_bindings()
      |> Enum.map(fn
          {name, :input, _, _, _, default, _} ->
        if default == :__mazurka_unspecified do
          {name, Utils.hidden_var(name)}
        else
          {name, Macro.var(name, nil)}
        end

        {name, _, _, _, _, _default, _} ->
          {name, Macro.var(name, nil)}
      end)
      |> Map.new()
      |> Enum.to_list()

    if type == :atom do
      quote do
        unquote({:%{}, [], all_bindings})
      end
    else
      quote do
        unquote({:%{}, [], all_bindings |> Enum.map(fn {k, v} -> {to_string(k), v} end)})
      end
    end
  end
end
