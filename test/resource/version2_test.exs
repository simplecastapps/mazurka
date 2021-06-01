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
    {_body, _, _} = Foo.action([], %{"param1" => 2}, %{"input1" => 1, "input5" => "input5!", "input3" => 3}, %{})
  end
end
