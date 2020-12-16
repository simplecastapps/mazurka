defmodule Mazurka.Resource.Condition do
  @moduledoc false

  alias Mazurka.Resource.Utils.Scope

  defmacro condition(block, message \\ nil)

  defmacro condition([do: block], message) do
    Scope.define(nil, nil, nil, :condition, block, message, nil, nil)
  end

  defmacro condition(block, message) do
    Scope.define(nil, nil, nil, :condition, block, message, nil, nil)
  end
end
