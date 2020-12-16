#defmodule Mazurka.Resource.Utils.Check do
#  @moduledoc false
#
#  defmacro __using__(_) do
#    module = __CALLER__.module
#    name = Module.split(module) |> List.last()
#
#    quote bind_quoted: binding(), do
#      alias Mazurka.Resource.Utils
#      alias Utils.Scope
#
#      defmacro __using__(_) do
#        quote do
#          import unquote(__MODULE__)
#        end
#      end
#    end
#  end
#end
