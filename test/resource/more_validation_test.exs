defmodule Test.Mazurka.Resource.MoreValidation do
  use Test.Mazurka.Case

  def positive_integer(x) do
    msg = "must be an integer greater than 0"
    case x do
      _ when is_integer(x) and x > 0 -> {:ok, x}
      _ when is_binary(x) ->
        x |> Integer.parse() |> case do
          {i, _} when i > 0 -> {:ok, i}
          _ -> {:error, msg}
        end
      _ ->
        {:error, msg}
    end
  end
  def positive_integer(x, opts) do
    x |> positive_integer() |> case do
      {:ok, _} = x -> x
      {:error, msg} -> {:error, "#{opts[:var_type]} #{opts[:field_name]} #{msg}"}
    end
  end

  context "Simple" do
    defmodule Foo do
      use Mazurka.Resource
      alias Test.Mazurka.Resource.MoreValidation

      param param1, condition: fn x ->
        if x do
          {:ok, x * 2}
        else
          {:error, "not_found"}
        end
      end

      input input1, default: "default!", validation: fn x ->
        {:ok, x + param1}
      end

      input input2, validation: &MoreValidation.positive_integer/2
      input input3, validation: &MoreValidation.positive_integer/1
      input input4, validation: fn x, _opts ->
        # {:ok, input3} # compile error, no such variable
        {:ok, x}
      end

      input input5, validation: fn x, _opts ->
        {:ok, x}
      end

      let input5 = "input5"

      param param2, condition: fn _x ->
        if input1 do
          {:ok, input1}
        else
          {:error, "param2 error"}
        end
      end

      # can't reference a validation variable in a condition
      #input input2 condition fn x ->
      #  {:ok, x + input1}
      #end

      let let0 = "let0"
      let let1, condition: fn ->
        {:ok, param1}
      end
      let let2, validation: fn ->
        {:ok, input1}
      end

      let let3, validation: fn ->
        {:ok, "let3"}
      end

      input let4, validation: fn _ ->
        {:ok, "let4 binding will be overwritten by next statement"}
      end

      let let4 do
        "let4 binding will be overwritten too"
      end

      let let4 do
        "let4"
      end



      mediatype Hyper do
        affordance do
          %{
            "param1" => param1,
            # none of these exist because they involve validations
            # which don't exist in an affordance
            #
            # "all_input" => Input.all()
            # exist in affordances
            # "input1" => input1
            # "let4" => let4
          }
        end
        action do
          %{
            "param1" => param1,
            "param1_from_get" => Input.get(:param1),
            "input1" => input1,
            "let0" => let0,
            "let1" => let1,
            "let2" => let2,
            "let3" => let3,
            "let4" => let4,
            "all_input" => Input.all(),
            "all_lets" => Mazurka.Resource.Let.all(),
            "all_bindings" => Mazurka.Resource.Option.all_bindings()
          }
        end
      end
    end

    router Router do
      route "GET", ["param1", :param1], Foo
    end

  after
    "action" ->
    {body, _, _} = Foo.action([], %{"param1" => 2, "param2" => 3}, %{"input1" => 1, "input2" => 2, "input3" => 3}, %{})

    assert body == %{
      "param1" => 4,
      "param1_from_get" => 4,
      "input1" => 5,
      "let0" => "let0",
      "let1" => 4,
      "let2" => 5,
      "let3" => "let3",
      "let4" => "let4",
      "all_input" => %{input1: 5, input2: 2, input3: 3},
      "all_lets" => %{
        let0: "let0",
        let1: 4,
        let2: 5,
        let3: "let3",
        let4: "let4",
        input5: "input5"
      },
      "all_bindings" => %{
        param1: 4,
        param2: 5,
        input1: 5,
        input2: 2,
        input3: 3,
        # input4 missing because it is an input that was not sent
        input5: "input5", # in bindings because of let
        let0: "let0",
        let1: 4,
        let2: 5,
        let3: "let3",
        let4: "let4"
      }
    }

    "affordance" ->
    {body, _} = Foo.affordance([], %{"param1" => 2, "param2" => 3}, %{"input1" => "1"}, %{}, Router)

    assert body == %{"param1" => 4, "href" => "/param1/2?input1=1"}

    "action with various failure conditions" ->

    exc = assert_raise Mazurka.ValidationException, fn ->
      Foo.action([], %{"param1" => 2, "param2" => 3}, %{"input1" => 1, "input2" => "-1"}, %{})
    end
    assert exc.message ==  "input input2 must be an integer greater than 0"

    exc = assert_raise Mazurka.ValidationException, fn ->
      Foo.action([], %{"param1" => 2, "param2" => 3}, %{"input1" => 1, "input2" => "1", "input3" => -2}, %{})
    end
    # input3 uses a slightly different validation function that input2
    assert exc.message ==  "must be an integer greater than 0"

    assert Foo.params() |> Enum.sort == [:param1, :param2] |> Enum.sort
    assert Foo.params(:binary) |> Enum.sort == ["param1", "param2"] |> Enum.sort
    assert Foo.inputs() |> Enum.sort == [:input1, :input2, :input3, :input4, :input5, :let4] |> Enum.sort
    assert Foo.inputs(:binary) |> Enum.sort == ["input1", "input2", "input3", "input4", "input5", "let4"] |> Enum.sort


    #     "affordance" ->
    #       assert {_, _} = Foo.affordance([], %{"param1" => "param1"}, %{}, %{}, Router)
    #
    #     "affordance validation success" ->
    #       assert {_, _} = Foo.affordance([], %{"param1" => "bar"}, %{}, %{}, Router)
  end
end
