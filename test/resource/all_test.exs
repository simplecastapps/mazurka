defmodule Test.Mazurka.Resource.All do
  use Test.Mazurka.Case

  context Various do
    defmodule Foo do
      use Mazurka.Resource

      version 1

      let input1_unaltered1 = Input.retrieve_unaltered(:input1)

      param param1, fn x -> x <> "baz" end
      input input1, fn x -> x <> "bar" end
      # an empty input
      input input2

      let input1_unaltered2 = Input.retrieve_unaltered(:input1)

      input inputa, fn x ->
        cond do
          x == "true" -> true
          x == "false" -> false
          true -> nil
        end
      end

      input inputb, fn x ->
        cond do
          x == "true" -> true
          x == "false" -> false
          true -> nil
        end
      end

      input inputc, fn _x -> nil end
      input inputd, fn _x -> true end

      let option = Mazurka.Resource.Option.get(:option1) <> "asdf"

      mediatype Hyper do
        action do
          key = :input1

          %{
            input1_var: input1,
            input1: Input.get(:input1),
            by_code: Input.get(key),
            all_atom: Input.all(),
            all_binary: Input.all(:binary),
            option1: Mazurka.Resource.Option.get(:option1),
            let_option: option,
            input1_unaltered_1: input1_unaltered1,
            input1_unaltered_2: input1_unaltered2
          }
        end
      end
    end
  after
    "action" ->
      {body, _, _} =
        Foo.action(
          [],
          %{
            "param1" => "bar"
          },
          %{
            "unspecifiedinput" => "yo",
            "input1" => "foo",
            "inputa" => "true",
            "inputb" => "false",
            "inputc" => "anything"
          },
          %{},
          nil,
          %{
            :option1 => "option1"
          }
        )

      assert %{
               # input modified by any functions by any attached input statement functions
               input1_var: "foobar",
               input1: "foobar",
               # input with key generated from runtime code
               by_code: "foobar",

               # all specified inputs represented with atom keys, no unspecified keys
               all_atom: %{
                 :input1 => "foobar",
                 # a present because "true" specified converted to bool
                 # b present because "false" specified converted to bool
                 # c present because specified anything at all unconditionally converted to nil
                 # d not present because it wasn't passed into route
                 :inputa => true,
                 :inputb => false,
                 :inputc => nil
               },

               # all specified inputs represented with binary keys, no unspecified keys
               all_binary: %{
                 "input1" => "foobar",
                 "inputa" => true,
                 "inputb" => false,
                 "inputc" => nil
               },

               # option fetched as original option, unmodified
               option1: "option1",

               # option used as variable which has been modified
               let_option: "option1asdf",

               # unaltered input (function not run on it, but can be used anywhere in module)
               input1_unaltered_1: "foo",
               input1_unaltered_2: "foo"
             } == body
  end

  context LetBeforeInput do
    defmodule Foo do
      use Mazurka.Resource

      let param1 = 2

      param param1, condition: fn _x ->
        {:ok, 123}
      end

      let input1 = 2

      input input1, condition: fn _x ->
        {:ok, 123}
      end

      let input2 = 2

      input input2, default: nil, condition: fn _x ->
        {:ok, 123}
      end

      mediatype Hyper do
        action do
          %{
            all_input: Input.all(),
            all_params: Params.all(),
            param1: param1,
            input1: input1,
            input2: input2
          }
        end
      end
    end
  after
    "action" ->
      {body, _, _} =
        Foo.action(
          [],
          %{
            "param1" => 1
          },
          %{
            "input1" => 1
          },
          %{},
          nil,
          %{}
        )

      assert %{
               param1: 123,
               # value from let, input skipped because no default on input1
               input1: 2,
               # value from input condition, not skipped because input2 has a default
               input2: 123,
               all_input: %{
                 # value from input1 condition, here because it was supplied
                 input1: 123
                 # input2 is missing because it was not supplied
               },
               all_params: %{
                 param1: 123
               }
             } == body
  end

  context LetBeforeInput2 do
    defmodule Foo do
      use Mazurka.Resource

      let param1 = 2

      param param1, condition: fn _x ->
        {:ok, 123}
      end

      let input1 = 2

      # because there is no default, this is hidden from action
      input input1, condition: fn _x ->
        {:ok, 123}
      end

      let input2 = 2

      input input2,
        default: 123,
        condition: fn _x ->
          {:ok, 123}
        end

      mediatype Hyper do
        action do
          %{
            all_input: Input.all(),
            all_params: Params.all(),
            param1: param1,
            # ends up being the let input1, not the input input1
            input1: input1,
            input2: input2
          }
        end
      end
    end
  after
    "action" ->
      {body, _, _} =
        Foo.action(
          [],
          %{
            "param1" => 1
          },
          %{},
          %{},
          nil,
          %{}
        )

      assert %{
               input1: 2,
               input2: 123,
               param1: 123,
               all_input: %{},
               all_params: %{
                 param1: 123
               }
             } == body
  end
end
