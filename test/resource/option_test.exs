defmodule Test.Mazurka.Resource.Option do
  use Test.Mazurka.Case

  context Single do
    defmodule Foo do
      use Mazurka.Resource

      option foo

      mediatype Hyper do
        action do
          %{"foo" => foo}
        end
      end
    end
  after
    "action" ->
      {body, content_type, _} = Foo.action([], %{}, %{}, %{}, nil, %{foo: "123"})
      assert %{"foo" => "123"} == body
      assert {"application", "json", %{}} = content_type

    "action missing param" ->
      {body, _, _} = Foo.action([], %{}, %{}, %{})
      assert %{"foo" => nil} = body
  end
end
