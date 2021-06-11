defmodule Mazurka.Resource.Param do
  @moduledoc false

  # expose the params getter
  alias Mazurka.Resource.Utils
  use Utils.Global, var: :params
  alias Utils.Scope

  defmacro __using__(_) do
    %{module: module} = __CALLER__
    Module.register_attribute(module, :mazurka_params, accumulate: true)

    quote do
      require unquote(__MODULE__)
      alias unquote(__MODULE__), as: Params
      import unquote(__MODULE__), only: [param: 1, param: 2]

      @before_compile unquote(__MODULE__)

      def params(type \\ :atom) do
        case type do
          :atom -> @mazurka_params |> Enum.uniq()
          :binary -> @mazurka_params |> Enum.uniq() |> Enum.map(&to_string/1)
        end
      end
    end
  end

  @doc """
  Define an expected parameter for the resource

      param user

      param user, &User.get(&1)

      param user, fn(value) ->
        User.get(value)
      end
  """
  def usage(module, line) do
    code = "In module #{module} line #{line}:\n"

    """
        #{code}
        Incorrect usage:
          param <paramname>, [opts]

        for documentation, type `h #{__MODULE__}.param`
    """
  end

  @doc """
  Define an expected input for the resource

      param address, validation: fn value ->
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


      param address, validation: fn x, field_name, param_type ->
        :address = field_name
        :param = param_type
        value ->
        case value |> parse_address() do
          %Address{} = addr -> {:ok, addr}
          _ ->
            # "validation: Could not parse input address"
            msg = "\#{validation_type}: Could not parse \#{param_type} address"
            {:error, msg}
        end
      end

      param foo, option: true, default: "foo", validation: fn x ->
        {:ok, x |> to_string()}
      end

    Options:
    * `condition` function with between 1 and 3 params returning {:ok, val} or {:error, message}
    * `validation` same as condition, but only run in actions, not affordances

    * `option` if true, use options passed into this route with the same name. If an atom, use options passed in of that name. If list of atoms, use first option passed in that matches. If no matches, do validation / condition as normal with user passed in value.


    Since it is a param, it will always be brought into scope, but to be accessible as a variable
    its condition or validation must have run.

    There must be at least one validation or condition but not both. If the variable is validated, then it will not be brought into scope in affordances or in any other let / param / input condition code. This is to prevent referencing an unvalidated variable in a context where validation did not occur. 
  """
  defmacro param(w, opts \\ []) do
    module = __CALLER__.module
    version = module |> Module.get_attribute(:mazurka_version)

    # backwards compatibility with version 1
    opts =
      cond do
        version < 2 ->
        case opts do
          # `param param1` - no code block
          [] ->
            [
              condition:
                quote do
                  fn x -> {:ok, x} end
                end
            ]

          # `param param1, fn x -> x end - code block always run, nil if not specified
          {op, _, _} = block when op in [:&, :fn] ->
            [
              condition:
                quote do
                  fn x -> {:ok, unquote(block).(x)} end
                end
            ]

          x ->
            x
      end
        is_list(opts) ->
          # default is not supported in params except as a backwards compatibility hack
        opts |> Keyword.delete(:default)
        true ->
          raise "FOrmat for param #{field_to_atom(w)} is incompatible with this verison of mazurka. Type h #{__MODULE__}.param/2 for more information."
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
          raise "You must specify at least one of a validation or condition in the param #{name}"

        validation != :__mazurka_unspecified ->
          {:validation, validation}

        true ->
          {:condition, condition}
      end

    module = __CALLER__.module
    Module.put_attribute(module, :mazurka_params, name)
    Scope.define(module, Utils.params(), name, :param, val_type, block, nil, default, option_fields)
  end

  defp field_to_atom({name, _, nil}) when is_atom(name) do
    name
  end

  defp field_to_atom(name) when is_atom(name) do
    name
  end

  defmacro __before_compile__(env) do
    case Module.get_attribute(env.module, :mazurka_params) do
      [] ->
        quote do
          defp __mazurka_filter_params__(_params) do
            %{}
          end

          defp __mazurka_check_params__(_params) do
            {[], []}
          end
        end

      [name] ->
        bin_name = name |> to_string()

        quote do
          defp __mazurka_filter_params__(params) do
            case params |> Map.fetch(unquote(bin_name)) do
              {:ok, val} -> %{unquote(name) => val}
              :error -> %{}
            end
          end

          defp __mazurka_check_params__(params) do
            Mazurka.Resource.Param.__check_param__(params, unquote(name), [], [])
          end
        end

      names ->
        bin_names = names |> Enum.map(&to_string/1)

        checks =
          names
          |> Enum.map(fn name ->
            quote do
              {missing, nil_params} =
                Mazurka.Resource.Param.__check_param__(params, unquote(name), missing, nil_params)
            end
          end)

        quote do
          defp __mazurka_filter_params__(params) do
            params
            |> Enum.filter(fn {k, _v} ->
              k in unquote(bin_names)
            end)
            |> Enum.map(fn {k, v} ->
              {k |> String.to_existing_atom(), v}
            end)
            |> Map.new()
          end

          defp __mazurka_check_params__(params) do
            params =
              params
              |> Enum.filter(fn {k, _v} ->
                k in unquote(names)
              end)
              |> Map.new()

            missing = []
            nil_params = []
            unquote_splicing(checks)
            {missing, nil_params}
          end
        end
    end
  end

  def __check_param__(params, name, missing, nil_params) when is_atom(name) do
    case Map.fetch(params, name) do
      :error ->
        {[name | missing], nil_params}

      {:ok, nil} ->
        {missing, [name | nil_params]}

      _ ->
        {missing, nil_params}
    end
  end

  @doc """
    This returns all validated (via condition) parameters.

    Returned as a Map(:atom => :term), where every key is a param
    in the route route and every term was either submitted by the user
    and has been validated properly or was passed in as an option
    via link_to (or option: feature) in a prior route (and is
    therefore trustworthy).

    * type - Return keys as strings or atoms. Strings option is there fore
    backward compatibility only.

    This can only be used in the action or affordance blocks of a route because
    it returns the final validated values of all variables after they have been
    manipulated by various param and let statements defined in the route.
  """
  defmacro all(type \\ :atom) do
    # keyword list from variable atom to stored variable name
    all_params =
      __CALLER__.module
      |> Module.get_attribute(:mazurka_scope)
      |> Enum.reverse()
      |> Mazurka.Resource.Utils.Scope.filter_by_params()
      |> Enum.map(fn {_var, name, :param, _, _, _, _default, _} ->
          {name, Macro.var(name, nil)}
      end)

    if type == :atom do
      quote do
        unquote({:%{}, [], all_params})
      end
    else
      quote do
        unquote({:%{}, [], all_params |> Enum.map(fn {k, v} -> {to_string(k), v} end)})
      end
    end
  end

  defmacro all_unaltered() do
    Utils.params()
  end
end
