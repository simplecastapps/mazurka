defmodule Test.Mazurka.Resource.Me do
  use Test.Mazurka.Case

  context Single do
    defmodule Foo do
      use Mazurka.Resource

      # Right now it does params
      # then inputs
      # then lets
      # then conditions


      # what we want is
      # 1 ensure all params present
      # 2 in actions
      #   params, inputs, conditions, validations interleaved
      # 2 in affordances
      #   params, inputs, conditions interleaved

      param param1, (fn param1 -> IO.puts("\nparam param1"); param1 end)
      param param2, (fn param2 -> IO.puts("\nparam param2"); param2 end)
      input foo1, (fn foo1 -> IO.puts("input foo1"); foo1 end)

      validation (IO.puts("validation #{foo1}"); foo1 == "123"), "some_error1"
      condition (IO.puts("condition"); foo1 == "123"), "some_error2"
      input foo3, fn _ -> IO.puts("input foo3"); foo1 end

      let foo2 = (IO.puts("let foo2"); 123)

      let foo = (IO.puts("let foo"); foo1)
      validation (IO.puts("validation 2"); foo1 == "123"), "some_error3"

      mediatype Hyper do
        action do
          %{
                  "foo1" => foo1,
            "foo2" => foo2,
            "foo3" => foo3
          }
        end
      end
    end
    router Router do
      route "GET", ["param1", :param1, "param2", :param2], Foo
    end
  after
      "action - mixed lets conditions - no error" ->
  
        {body, content_type, _} = Foo.action([], %{"param1" => "asdf", "param2" => "param2"}, %{"foo1" => "123"}, %{})
        #        assert {"application", "json", %{}} = content_type
        #      assert %{
        #        "foo1" => "123",
        #        "foo2" => 123,
        #        "foo3" => "123",
        #        "param1" => "asdf",
        #        "param2" => "param2",
        #      } == body

      #  "affordance mixed lets conditions - no error" -> nil
      #    {body, content_type} = Foo.affordance([], %{"param1" => "asdf", "param2" => "param2"}, %{"foo1" => "123"}, %{}, Router)
      #    assert {"application", "json", %{}} = content_type
      #  assert %{
      #    "href" => "/param1/asdf/param2/param2?foo1=123",
      #  } == body



    #    "mixed lets conditions - current condition failure" ->
    #      try do
    #        {body, content_type, _} = Foo.action([], %{}, %{"foo1" => "asdf"}, %{})
    #      rescue
    #        e in [ArgumentError] ->
    #          assert e.message == "argument error"
    #      end

    #"mixed lets conditions - desired condition failure" ->
    #  try do
    #    {body, content_type, _} = Foo.action([], %{}, %{"foo1" => "asdf"}, %{})
    #  rescue
    #    e in [Mazurka.ConditionException] ->
    #      assert e.message == "some_error"
    #  end

  end
end
