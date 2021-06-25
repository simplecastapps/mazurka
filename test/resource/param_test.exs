defmodule Test.Mazurka.Resource.Param do
  use Test.Mazurka.Case

  context Single do
    defmodule Foo do
      use Mazurka.Resource

      version 1

      param foo

      mediatype Hyper do
        action do
          %{"foo" => foo}
        end
      end
    end
  after
    "action" ->
      {body, content_type, _} = Foo.action([], %{"foo" => "123"}, %{}, %{})
      assert %{"foo" => "123"} == body
      assert {"application", "json", %{}} = content_type

    "action missing param" ->
      assert_raise Mazurka.MissingParametersException, fn ->
        Foo.action([], %{}, %{}, %{})
      end

    "action nil param" ->
      assert_raise Mazurka.MissingParametersException, fn ->
        Foo.action([], %{"foo" => nil}, %{}, %{})
      end

    "affordance" ->
      assert_raise Mazurka.MissingRouterException, fn ->
        Foo.affordance([], %{"foo" => "123"}, %{}, %{})
      end

    "affordance missing param" ->
      assert_raise Mazurka.MissingParametersException, fn ->
        Foo.affordance([], %{}, %{}, %{})
      end

    "affordance nil param" ->
      {body, _} = Foo.affordance([], %{"foo" => nil}, %{}, %{})
      assert %Mazurka.Affordance.Undefined{} = body
  end

  context Transform do
    defmodule Foo do
      use Mazurka.Resource

      version 1

      param foo, fn(value) ->
        [value, value]
      end

      param bar, &[&1, &1]

      mediatype Hyper do
        action do
          %{
            "bar" => bar,
            "foo" => foo
          }
        end
      end
    end
  after
    "action" ->
      {body, _, _} = Foo.action([], %{"foo" => "123", "bar" => "456"}, %{}, %{})
      assert %{"bar" => ["456", "456"], "foo" => ["123", "123"]} = body
  end

  context Referential do
    defmodule Foo do
      use Mazurka.Resource

      version 1

      param foo

      param bar, fn(value) ->
        [foo, value]
      end

      mediatype Hyper do
        action do
          %{
            "bar" => bar
          }
        end
      end
    end
  after
    "action" ->
      {body, _, _} = Foo.action([], %{"foo" => "123", "bar" => "456"}, %{}, %{})
      assert %{"bar" => ["123", "456"]} = body
  end
end
