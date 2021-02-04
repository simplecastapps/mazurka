defmodule Mazurka.Resource.Utils.Global do
  @moduledoc false

  defmacro __using__(opts) do
    var_name = opts[:var]

    var_module = __CALLER__.module

    # if raw, Foo.get/1 can be used in lets / conditions but will be unaltered
    # if block, Foo.get can only be used in action block, but will be altered
    # by various lets, functions (eg. input foo, &func/1) along the way
    # :block | :raw
    style = opts[:style] || :block

    quote bind_quoted: binding() do
      require Mazurka.Resource.Utils

      defmacro has(name) when is_atom(name) do
        value = Mazurka.Resource.Utils.unquote(var_name)()

        quote do
          unquote(value) |> Map.has_key?(unquote(name))
        end
      end

      if style == :block do
        defmacro get(name) when is_atom(name) do
          Macro.var(name, nil)
        end

        defmacro get(name) when is_binary(name) do
          Macro.var(name |> String.to_atom(), nil)
        end

        defmacro get(code) do
          mod = unquote(var_module)
          quote do
            unquote(mod).all() |> Map.get(unquote(code))
          end
        end

        defmacro all_unaltered() do
          Mazurka.Resource.Utils.unquote(var_name)()
        end

        # Allows :block style to retrieve in lets but
        # it will be unaltered by functions attached to statements
        defmacro retrieve_unaltered(name) when is_atom(name) do
          value = Mazurka.Resource.Utils.unquote(var_name)()

          quote do
            unquote(value)[unquote(name)]
          end
        end

        defmacro retrieve_unaltered(name) when is_binary(name) do
          value = Mazurka.Resource.Utils.unquote(var_name)()
          name = String.to_atom(name)

          quote do
            unquote(value)[unquote(name)]
          end
        end

        defmacro retrieve_unaltered(name) do
          value = Mazurka.Resource.Utils.unquote(var_name)()

          quote do
            unquote(value)[unquote(name)]
          end
        end
      else
        defmacro get(name) when is_atom(name) do
          value = Mazurka.Resource.Utils.unquote(var_name)()

          quote do
            unquote(value)[unquote(name)]
          end
        end

        defmacro get(name) when is_binary(name) do
          value = Mazurka.Resource.Utils.unquote(var_name)()
          name = String.to_atom(name)

          quote do
            unquote(value)[unquote(name)]
          end
        end

        defmacro get(name) do
          #value = Mazurka.Resource.Utils.unquote(var_name)()

          quote do
            nil
            # value = unquote(value)

            # case unquote(name) do
            #   name when is_atom(name) ->
            #     value[name]

            #   name when is_binary(name) ->
            #     value[String.to_existing_atom(name)]
            # end
          end
        end
      end
    end
  end
end
