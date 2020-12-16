defmodule Test.Mazurka.Resource.Mixed do
  use Test.Mazurka.Case

  context "Simple" do
    defmodule Foo do
      use Mazurka.Resource

      version 1

      param foo
      condition foo != "bar"

      let a do
        if foo == "bar" do
          throw "this should not get hit"
        else
          foo
        end
      end

      mediatype Hyper do
        action do
          %{
            "foo" => foo,
            "a" => a
          }
        end
      end
    end

    comment """
    We'll also set up a router so we can observe how affordances work with failed conditions.
    """

    defmodule Router do
      def resolve(%{resource: Foo, params: %{"foo" => foo}} = affordance, _source, _conn) do
        %{affordance | method: "GET", path: "/foo/#{foo}"}
      end
    end
  after
    "success" ->
      {response, _content_type, _conn} = Foo.action([], %{"foo" => "baz"}, %{}, %{}, Router)
      assert %{"foo" => "baz", "a" => "baz"} = response

      "condition fail before let" ->
      assert_raise( Mazurka.ConditionException, fn ->
        {_response, _content_type, _conn} = Foo.action([], %{"foo" => "bar"}, %{}, %{}, Router)
      end)

  end
end
