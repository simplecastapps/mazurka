defmodule Test.Mazurka.Resource.Let do
  use Test.Mazurka.Case

  context Basic do
    defmodule Foo do
      use Mazurka.Resource

      let foo = 1

      let bar do
        a = 1
        foo + a
      end

      mediatype Hyper do
        action do
          %{"foo" => bar}
        end
      end
    end
  after
    "Foo.action" ->
      {body, _, _} = Foo.action([], %{}, %{}, %{})
      assert %{"foo" => 2} == body
  end

  context Validations do
    defmodule Foo do
      use Mazurka.Resource

      let foo = "foo"

      let bar, validation: fn ->
        if foo == "foo" do
          {:ok, "bar"}
        else
          {:error, "nope"}
        end
      end

      condition foo == "foo", "foo"
      condition foo == "foo", on_error: "foo"
      condition on_error: "foo" do
        foo == "foo"
      end

      let letval, validation: fn ->
        {:ok, 123}
      end

      validation letval, "error"

      # would fail to compile, accessing validation from condition code
      # condition bar == "bar", "asdf"

      mediatype Hyper do
        action do
          %{foo: foo, bar: bar}
        end
      end
    end
  after
    "Foo.action" ->
      {body, _, _} = Foo.action([], %{}, %{}, %{})
      assert %{foo: "foo", bar: "bar"} == body
  end
end
