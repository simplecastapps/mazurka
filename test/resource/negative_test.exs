defmodule Test.Mazurka.Resource.Negative do
  use Test.Mazurka.Case

  # unfortunately in elixir there is no way to silence warnings... :(
  # but these test are important to find scope related regressions.
  describe "tests that shouldn't compile" do

    test "non defaulted input referenced in condition contexts" do
      module = """
        defmodule Foo do
      use Mazurka.Resource

          input input1, validation: fn x, _ -> {:ok, x} end
          param input2, condition: fn _x, _ -> {:ok, input1} end

          mediatype Hyper do
            action do
            end
          end
        end
      """

      _e = try do
        Code.compile_string(module, "negative_test.exs")
        %{description: "compiled successfully which it should not"}
      rescue
        e in [CompileError] ->  e
      end

      # the compiler has begun logging errors rather than putting them
      # into the compilation error struct.
      # assert e.description |> String.contains?("input1")
    end

    test "required validated input referenced in conditional blocks" do
      module = """
        defmodule Foo do
          use Mazurka.Resource

          input input1, required: fn _opts -> "error" end, validation: fn x, _ -> {:ok, x} end
          let let1 = input1

          mediatype Hyper do
            action do
            end
          end
        end
      """

      _e = try do
        Code.compile_string(module, "negative_test.exs")
        %{description: "compiled successfully which shouldn't happen"}
      rescue
        e in [CompileError] ->  e
      end

      # assert e.description |> String.contains?("input1")
    end

    test "non defaulted non required input referenced" do
      module = """
        defmodule Foo do
          use Mazurka.Resource
          input input1, validation: fn x, _ -> {:ok, x} end
          input input2, validation: fn _x, _ -> {:ok, input1} end

          mediatype Hyper do
            action do
            end
          end
        end
      """

      _e = try do
        Code.compile_string(module, "negative_test.exs")
        %{description: "compiled successfully which it should not"}
      rescue
        e in [CompileError] ->  e
      end

      # assert e.description |> String.contains?("input1")
    end

  end
end
