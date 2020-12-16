defmodule Mazurka.Resource.Version do
  @moduledoc false

  @current_version 2

  defmacro __using__(_) do
    %{module: module} = __CALLER__
    Module.register_attribute(module, :mazurka_version, [])
    Module.put_attribute(module, :mazurka_version, @current_version)

    quote do
      require unquote(__MODULE__)
      import unquote(__MODULE__), only: [version: 1]
    end
  end

  @doc """
  As mazurka changes, its version goes up and this allows routes
  to set api version of mazurka so that it parses inputs correctly.
  """
  defmacro version(x) when is_integer(x) do
    module = __CALLER__.module
    Module.put_attribute(module, :mazurka_version, x)
    nil
  end
end
 
