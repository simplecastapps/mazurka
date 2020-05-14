defmodule Mazurka.Resource.Validation do
  @moduledoc false

  use Mazurka.Resource.Utils.Check

  defmacro validation(block, message \\ nil) do
    Scope.check(:validation, block, if message do message else block end)
  end
end
