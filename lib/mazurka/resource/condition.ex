defmodule Mazurka.Resource.Condition do
  @moduledoc false

  alias Mazurka.Resource.Utils.Scope

  @doc """
  This is for "naked" conditions which merely evaluate a statement and if it is falsey,
  then the route is aborted with the supplied error message.

  Usage:
      let foo = (1 == 2)
      condition foo, "error message"

      let bar = (1 == 1)
      condition bar, "this would not error"

      let quux = nil
      condition quux, "this would error too"

  In case you have a large block of code for the condition, you can use do syntax, but
  you must specify the error as an option. This is merely due to a limitation of do syntax
  in elixir... it must come last.
      condition on_error: "error_message" do
        # long block of condition code that returns true or false
        true
      end

  Or for short conditions, you can spell it out, if you really want to.
      condition 1 != 2, on_error: "error message"

  Warning: Note that conditions cannot access as variables any that are tied
  to validations!  That is because conditions are always evaluated, but
  validations are only evaluated sometimes.

      # though these variables always exist, they are not always validated!
      param foo, validation: {:ok, 123}
      let foo2, validation: {:ok, 123}

      # fails to compile, validations above might not have run
      # so these variables are not in condition scope!
      condition foo != 123, "error_message"
      condition foo2 != 123, "error_message"

      # this is fine because we know foo was validated by previous statements
      # and must exist at this point.
      validation foo != 123, "error_message"
  """
  defmacro condition(first_arg, second_arg \\ :__mazurka_unspecified) do
    module = __CALLER__.module
    version = module |> Module.get_attribute(:mazurka_version)

    if version >= 2 && second_arg == :__mazurka_unspecified do
      raise "conditions must have an error message!"
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
        # condition on_error: "error_message do foo end
        is_list(first_arg) && first_arg[:on_error] ->
          {first_arg[:on_error], second_arg}

        # condition foo, on_error: "error_message
        is_list(second_arg) && second_arg[:on_error] ->
          {second_arg[:on_error], first_arg}

        # condition foo, "error_message"
        true ->
          {second_arg, first_arg}
      end

    Scope.define(module, nil, nil, nil, :condition, block, message, :__mazurka_unspecified, nil)
  end
end
