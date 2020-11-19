defmodule Mazurka.Resource.Utils.Global do
  @moduledoc false

  defmacro __using__(opts) do
    var_name = opts[:var]

    # this supports old Foo.get() which passes through unspecified inputs
    # and thus has to return a map with string keys because it can't
    # convert unguarded input into atoms
    type = opts[:type] || :binary

    # if raw, Foo.get/1 can be used in lets / conditions but will be unaltered
    # if block, Foo.get can only be used in action block, but will be altered
    # by various lets, functions (eg. input foo, &func/1) along the way
    # :block | :raw
    style = opts[:style] || :block

    all_variable_map = ("mazurka_all_" <> to_string(var_name)) |> String.to_atom()

    quote bind_quoted: binding() do
      require Mazurka.Resource.Utils

      @deprecated "use (Params|Input).all(:binary) (or better yet :atom if you can)"
      defmacro get() do
        Mazurka.Resource.Utils.unquote(var_name)()
      end

      if style == :block do
        defmacro all(type \\ :atom) do
          x = Macro.var(unquote(all_variable_map), nil)

          case type do
            :atom ->
              x

            :binary ->
              quote do
                var!(unquote(x)) |> Enum.map(fn {k, v} -> {k |> to_string(), v} end) |> Map.new()
              end
          end
        end
      end

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
          x = Macro.var(unquote(all_variable_map), nil)

          quote do
            unquote(x) |> Map.get(unquote(code))
          end
        end

        # Allows :block style to retrieve in lets but
        # it will be unaltered by functions attached to statements
        defmacro retrieve_unaltered(name) when is_atom(name) do
          value = Mazurka.Resource.Utils.unquote(var_name)()
          name = to_string(name)

          quote do
            unquote(value)[unquote(name)]
          end
        end

        defmacro retrieve_unaltered(name) when is_binary(name) do
          value = Mazurka.Resource.Utils.unquote(var_name)()

          quote do
            unquote(value)[unquote(name)]
          end
        end

        defmacro retrieve_unaltered(name) do
          value = Mazurka.Resource.Utils.unquote(var_name)()

          quote do
            unquote(value)[to_string(unquote(name))]
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
          value = Mazurka.Resource.Utils.unquote(var_name)()

          quote do
            value = unquote(value)

            case unquote(name) do
              name when is_atom(name) ->
                value[name]

              name when is_binary(name) ->
                value[String.to_existing_atom(name)]
            end
          end
        end
      end
    end
  end
end
