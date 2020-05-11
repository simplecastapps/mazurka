defmodule Mazurka.Resource.Input do
  @moduledoc false

  alias Mazurka.Resource.Utils
  use Utils.Global, var: :input
  alias Utils.Scope

  defmacro __using__(_) do
    %{module: module} = __CALLER__
    Module.register_attribute(module, :mazurka_inputs, accumulate: true)
    quote do
      require unquote(__MODULE__)
      alias unquote(__MODULE__)
      import unquote(__MODULE__), only: [input: 1, input: 2]

      def inputs do
        @mazurka_inputs
      end
    end
  end

  @doc """
  Define an expected input for the resource

      input name

      input age, &String.to_integer(&1)

      input address, fn(value) ->
        Address.parse(value)
      end
  """

  defmacro input({name,_,_}, block \\ nil) do
    bin_name = name |> to_string()
    %{module: module} = __CALLER__
    #Module.put_attribute(module, :mazurka_inputs, bin_name)
    Module.put_attribute(module, :operations, {:input, {:assign, :input, name}})
    if block do
      Module.put_attribute(module, :operations, {:input, {:run_self, name, block}})
    end
    Scope.define(Utils.input, name, block)
  end
end
