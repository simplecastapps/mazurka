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

      @before_compile unquote(__MODULE__)

      def inputs(type \\ :atom) do
        case type do
          :atom -> @mazurka_inputs
          :binary -> @mazurka_inputs |> Enum.map(&to_string/1)
        end
      end
    end
  end

  defmacro __before_compile__(env) do
    case Module.get_attribute(env.module, :mazurka_inputs) do
      [] ->
        quote do
          defp __mazurka_filter_inputs__(_inputs) do
            %{}
          end
        end

      [name] ->
        bin_name = name |> to_string()

        quote do
          defp __mazurka_filter_inputs__(inputs) do
            case inputs |> Map.fetch(unquote(bin_name)) do
              {:ok, val} -> %{unquote(name) => val}
              :error -> %{}
            end
          end
        end

      names ->
        bin_names = names |> Enum.map(&to_string/1)

        quote do
          defp __mazurka_filter_inputs__(inputs) do
            inputs
            |> Enum.filter(fn {k, _v} ->
              k in unquote(bin_names)
            end)
            |> Enum.map(fn {k, v} -> {k |> String.to_existing_atom(), v} end)
            |> Map.new()
          end
        end
    end
  end

  def usage(module, line) do
    code = "In module #{module} line #{line}:\n"

    """
        #{code}
        Incorrect usage:
          input <inputname>, [opts]

        for documentation, type `h #{__MODULE__}.input`
    """
  end

  @doc """
  Define an expected input for the resource

      input address, validation: fn value ->
        case value |> parse_address() do
          %Address{} = addr -> {:ok, addr}
          {:error, reason} -> {:error, "Could not parse address because \#{reason}"}
          _ -> {:error, "Could not parse address"}
        end
      end

    Your validation function may optionally take up to two arguments.

    * the value passed in by the user
    * a set of options in which `:var_type` could be `:input` or `:param` and `:field_name` will be the name of the variable you are validating (in this case :address)

    Those options can be used to make more relevant error messages.


        input address, validation: fn x, opts ->
          :address = field_name
          :input = input_type

          value ->
          case value |> parse_address() do
            %Address{} = addr -> {:ok, addr}
            _ ->
              # "validation: Could not parse input address"
              msg = "\#{validation_type}: Could not parse \#{param_type} address"
              {:error, msg}
          end
        end

        input foo, option: true, default: "foo", validation: fn x ->
          {:ok, x |> to_string()}
        end

    Options:
    * `condition` function one or two parameters returning {:ok, val} or {:error, message}
    * `validation` same as condition, but only run in actions, not affordances
    * `default` if the user doesn't pass in a value, validation won't be run and this will be the default
    * `option` if true, use options passed into this route with the same name. If an atom, use options passed in of that name. If list of atoms, use first option passed in that matches. If no matches, do validation / condition as normal with the value that the user passed in.


    Since it is an input, which means by definition that it is optional, it will not be brought into scope unless it both has had its validation or condition run and has a default value set. You can find out if it was sent via `#{
    __MODULE__
  }.all()` which returns a map of variables that were sent, and you can access its value that way.

    There must be at least one validation or condition but not both. If the variable is validated and has no default, then it will not be brought into scope in affordances or in any other condition related code. This is to prevent referencing an unvalidated variable in a context where validation did not occur.
  """
  defmacro input(w, opts \\ []) do
    module = __CALLER__.module
    version = module |> Module.get_attribute(:mazurka_version)

    # backwards compatibility with version 1
    opts =
      cond do
        version < 2 ->
          case opts do
            # `input input1` - no code block
            [] ->
              [
                default: nil,
                condition:
                  quote do
                    fn x -> {:ok, x} end
                  end
              ]

            # - code block always run, nil if not specified
            # `input input1, fn x -> x end
            # `input input1, &IO.puts/1
            {op, _, _} = block when op in [:fn, :&] ->
              [
                default:
                  quote do
                    unquote(block).(nil)
                  end,
                condition:
                  quote do
                    fn x -> {:ok, unquote(block).(x)} end
                  end
              ]

            x ->
              x
          end

        is_list(opts) ->
          opts

        true ->
          raise "Format for input #{field_to_atom(w)} is incompatible with this verison of mazurka. Type h #{__MODULE__}.input/2 for more information."
      end

    name = field_to_atom(w)
    # option can be true (match current name), an atom, or a list of atoms
    option_fields =
      opts
      |> Keyword.get(:option, nil)
      |> case do
        nil -> []
        true -> [name]
        n when is_atom(n) -> [n]
        ns when is_list(ns) -> ns
        _ -> []
      end

    # We have to use :__maz_uns because it is perfectly valid to pass
    # eg. `default: nil`, or `let foo = nil`
    default =
      opts
      |> Keyword.fetch(:default)
      |> case do
        :error -> :__mazurka_unspecified
        {:ok, v} -> v
      end

    validation = Keyword.get(opts, :validation, :__mazurka_unspecified)
    condition = Keyword.get(opts, :condition, :__mazurka_unspecified)

    {val_type, block} =
      cond do
        validation != :__mazurka_unspecified && condition != :__mazurka_unspecified ->
          raise "You can't specify both a validation and condition block in input #{name}"

        validation == :__mazurka_unspecified && condition == :__mazurka_unspecified ->
          raise "You must specify at least one of a validation or condition in the input #{name}"

        validation != :__mazurka_unspecified ->
          {:validation, validation}

        true ->
          {:condition, condition}
      end

    Module.put_attribute(module, :mazurka_inputs, name)

    Scope.define(
      module,
      Utils.input(),
      name,
      :input,
      val_type,
      block,
      nil,
      default,
      option_fields
    )
  end

  defp field_to_atom({name, _, nil}) when is_atom(name) do
    name
  end

  defp field_to_atom(name) when is_atom(name) do
    name
  end

  defmacro all(type \\ :atom) do
    # keyword list from variable atom to stored variable name
    all_inputs =
      __CALLER__.module
      |> Module.get_attribute(:mazurka_scope)
      |> Enum.reverse()
      |> Mazurka.Resource.Utils.Scope.filter_by_inputs()
      |> Enum.map(fn {name, :input, _, _, _, default, _} ->
        if default == :__mazurka_unspecified do
          {name, Utils.hidden_var(name)}
        else
          {name, Macro.var(name, nil)}
        end
      end)

    if type == :atom do
      quote do
        supplied = unquote(Utils.input()) |> Map.keys()

        unquote(all_inputs)
        |> Enum.filter(fn {k, var} ->
          k in supplied
        end)
        |> Map.new()
      end
    else
      quote do
        supplied = unquote(Utils.input()) |> Map.keys()

        unquote(all_inputs)
        |> Enum.filter(fn {k, var} ->
          k in supplied
        end)
        |> Enum.map(fn {k, v} ->
          {k |> to_string(), v}
        end)
        |> Map.new()
      end
    end
  end
end
