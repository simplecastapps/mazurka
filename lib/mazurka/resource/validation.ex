defmodule Mazurka.Resource.Validation do
  @moduledoc false

  alias Mazurka.Resource.Utils.Scope

  @doc """
  This is for "naked" validations which merely evaluate a statement and if it is falsey,
  then the route is aborted with the supplied error message.

  Usage:
      let foo = (1 == 2)
      validation foo, "error message"

      let bar = (1 == 1)
      validation bar, "this would not error"

      let quux = nil
      validation quux, "this would error too"

  In case you have a large block of code for the validation, you can use do syntax, but
  you must specify the error as an option. This is merely due to a limitation of do syntax
  in elixir... it must come last.
      validation on_error: "error_message" do
        # long block of validation code that returns true or false
        true
      end

  Or for short validations, you can spell it out, if you really want to.
    validation 1 != 2, on_error: "error message"

  """
  defmacro validation(first_arg, second_arg \\ :__mazurka_unspecified) do
    module = __CALLER__.module
    version = module |> Module.get_attribute(:mazurka_version)

    if version >= 2 && is_nil(second_arg) do
      raise "validations must have an error message!"
    end

    # backwards compatibility
    first_arg =
      case first_arg do
        [do: block] -> block
        _ -> first_arg
      end

    second_arg =
      case second_arg do
        [do: block] -> block
        _ -> second_arg
      end

    {message, block} =
      cond do
        # validation on_error: "error_message do foo end
        is_list(first_arg) && first_arg[:on_error] ->
          {first_arg[:on_error], second_arg}

        # validation foo, on_error: "error_message
        is_list(second_arg) && second_arg[:on_error] ->
          {second_arg[:on_error], first_arg}

        # validation foo, "error_message"
        true ->
          {second_arg, first_arg}
      end

    Scope.define(nil, nil, nil, :validation, block, message, nil, nil)
  end
end
