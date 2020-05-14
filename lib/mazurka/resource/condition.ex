defmodule Mazurka.Resource.Condition do
  @moduledoc false

  use Mazurka.Resource.Utils.Check

  defmacro condition(block, message \\ nil) do
    Scope.check(:condition, block, if message do message else block |> Macro.to_string() end)
  end
end
