defmodule Test.Mazurka.Resource.Version2 do
  use Test.Mazurka.Case


  context "Simple" do
    defmodule Foo do
      def foobar(x) do
        x
      end

      use Mazurka.Resource
      version 1

      input input1
      input input1, fn x -> x end
      input input1, &foobar/1

      input input25, fn x -> if x do x else :nothing end end

      input input5, option: true, default: "default!", validation: fn x ->
        {:ok, x |> to_string()}
      end

      let asdf do
        # TODO inputs with default are visible
        {:ok, true}
      end

      param param1, option: true, validation: fn x ->
        {:ok, x}
      end
      #      input input2
      # input name, validation: fn _ -> {:ok, 123} end
      let name do
         "condition"
      end
      let name, condition: {:ok, "condition"}
      let name, condition: {:ok, Node.self()}
      let name, condition: {:ok, Node.self()}


      let foo2 do
      end

      let foo3, option: true do
      end

      input hidden_input, validation: fn x, _opts ->
        {:ok, x}
      end

      input input6,
      required: fn opts -> "required_message_#{opts[:var_type]}_#{opts[:field_name]}_#{opts[:validation_type]}" end,
        validation: fn x, _opts ->
          {:ok, x}
        end

      input input7, validation: fn x, _opts ->
        {:ok, input6 <> x}
      end

      input input8,
        required: fn opts -> "required_message_#{opts[:var_type]}_#{opts[:field_name]}_#{opts[:validation_type]}" end,
        condition: fn x, _opts ->
          {:ok, x}
        end


      mediatype Hyper do
        action do
          # param1 |> IO.inspect(label: "foo!")
          # Input.all() |> IO.inspect(label: "all")
          %{
            name: name
          }
        end
      end
    end

    router Router do
      route "GET", ["param1", :param1], Foo
    end

  after
    "action" ->
    {_body, _, _} = Foo.action([], %{"param1" => 2}, %{"input1" => 1, "input5" => "input5!", "input3" => 3, "input6" => "input6", "input8" => "input8"}, %{})

      try do
        {_body, _, _} = Foo.action([], %{"param1" => 2}, %{"input1" => 1, "input5" => "input5!", "input3" => 3}, %{})
      rescue
        e in [Mazurka.ValidationException] ->
          assert e.message == "required_message_input_input6_validation"
      end

      try do
        {_body, _, _} = Foo.action([], %{"param1" => 2}, %{"input1" => 1, "input5" => "input5!", "input3" => 3, "input6" => "input6"}, %{})
      rescue
        e in [Mazurka.ConditionException] ->
          assert e.message == "required_message_input_input8_condition"
      end

      {%{"href" => _}, _} = Foo.affordance([], %{"param1" => 2}, %{"input1" => 1, "input5" => "input5!", "input3" => 3, "input6" => "input6", "input8" => "input8"}, %{}, Router)

      # undefined because input8 is required and a condition but not supplied
      {%Mazurka.Affordance.Undefined{}, _} = Foo.affordance([], %{"param1" => 2}, %{"input1" => 1, "input5" => "input5!", "input3" => 3, "input6" => "input6"}, %{}, Router)

      # okay because even though input6 is required, it is not necessary for affordances
      {%{"href" => _}, _} = Foo.affordance([], %{"param1" => 2}, %{"input1" => 1, "input5" => "input5!", "input3" => 3, "input8" => "input8"}, %{}, Router)
  end
end
