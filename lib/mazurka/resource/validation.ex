defmodule Mazurka.Resource.Validation do
  @moduledoc false

  alias Mazurka.Resource.Utils.Scope

  defmacro validation(block, message \\ nil)

  defmacro validation([do: block], message) do
    Scope.define(nil, nil, nil, :validation, block, message, nil, nil)
  end

  defmacro validation(block, message) do
    Scope.define(nil, nil, nil, :validation, block, message, nil, nil)
  end
end
