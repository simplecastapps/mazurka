defmodule Test.Mazurka.Resource.Link do
  use Test.Mazurka.Case

  context "Dual" do
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

    defmodule Bar do
      use Mazurka.Resource

      version 1

      param bar

      mediatype Hyper do
        action do
          link = Foo
          %{
            "bar" => bar,
            "foo" => link_to(Foo, %{"foo" => bar <> bar}),
            "baz" => link_to(link, %{"foo" => bar})
          }
        end
      end
    end

    router Router do
      route "GET", ["foo", :foo], Foo
      route "POST", ["bar", :bar], Bar
    end
  after
    "Foo.action" ->
      {body, content_type, _} = Foo.action([], %{"foo" => "123"}, %{}, %{}, Router)
      assert %{"foo" => "123", "href" => "/foo/123"} == body
      assert {"application", "json", %{}} = content_type

    "Foo.affordance" ->
      {body, content_type} = Foo.affordance([], %{"foo" => "123"}, %{}, %{}, Router)
      assert %{"href" => "/foo/123"} == body
      assert {"application", "json", %{}} == content_type

    "Bar.action" ->
      {body, content_type, _} = Bar.action([], %{"bar" => "123"}, %{}, %{}, Router)
      assert %{"bar" => "123", "foo" => %{"href" => "/foo/123123"}, "baz" => %{"href" => "/foo/123"}, "href" => "/bar/123"} == body
      assert {"application", "json", %{}} == content_type

    "Bar.affordance" ->
      {body, content_type} = Bar.affordance([], %{"bar" => "123"}, %{}, %{}, Router)
      assert %{"action" => "/bar/123", "method" => "POST", "input" => %{}} = body
      assert {"application", "json", %{}} == content_type

    "Bar.action missing router" ->
      assert_raise Mazurka.MissingRouterException, fn ->
        Bar.action([], %{"bar" => "123"}, %{}, %{})
      end

    "Bar.affordance missing router" ->
      assert_raise Mazurka.MissingRouterException, fn ->
        Bar.affordance([], %{"bar" => "123"}, %{}, %{})
      end
  end

  context "Missing Param" do
    defmodule Foo do
      use Mazurka.Resource

      version 1

      param foo

      mediatype Hyper do
        action do
          %{}
        end
      end
    end

    defmodule Bar do
      use Mazurka.Resource

      mediatype Hyper do
        action do
          %{
            "foo" => link_to(Foo)
          }
        end
      end
    end
  after
    "Bar.action" ->
      assert_raise Mazurka.MissingParametersException, fn ->
        Bar.action([], %{}, %{}, %{})
      end
  end

  context "Nil Param" do
    defmodule Foo do
      use Mazurka.Resource

      version 1

      param foo

      mediatype Hyper do
        action do
          %{}
        end
      end
    end

    defmodule Bar do
      use Mazurka.Resource

      mediatype Hyper do
        action do
          %{
            "foo" => link_to(Foo, foo: nil)
          }
        end
      end
    end
  after
    "Bar.action" ->
      {res, _, _} = Bar.action([], %{}, %{}, %{})
      assert %{"foo" => %Mazurka.Affordance.Undefined{resource: Foo}} = res
  end

  context "Transition" do
    defmodule Foo do
      use Mazurka.Resource

      version 1

      param foo

      mediatype Hyper do
        action do
          %{}
        end
      end
    end

    defmodule Bar do
      use Mazurka.Resource

      mediatype Hyper do
        action do
          transition_to(Foo, foo: "123")
        end
      end
    end

    router Router do
      route "GET", ["foo", :foo], Foo
      route "POST", ["bar"], Bar
    end
  after
    "Foo.action" ->
      {_, _, conn} = Bar.action([], %{}, %{}, %{private: %{}}, Router)
      affordance = conn.private.mazurka_transition
      assert Foo = affordance.resource
      assert %{"foo" => "123"} == affordance.params
  end

  context "Invalidation" do
    defmodule Foo do
      use Mazurka.Resource

      version 1

      param foo

      mediatype Hyper do
        action do
          %{}
        end
      end
    end

    defmodule Bar do
      use Mazurka.Resource

      version 1

      param bar

      mediatype Hyper do
        action do
          %{}
        end
      end
    end

    defmodule Baz do
      use Mazurka.Resource

      mediatype Hyper do
        action do
          invalidates(Foo, foo: "123")
          invalidates(Bar, bar: "456")
        end
      end
    end

    router Router do
      route "GET", ["foo", :foo], Foo
      route "GET", ["bar", :bar], Bar
      route "GET", ["baz", :baz], Baz
    end
  after
    "Baz.action" ->
      {_, _, conn} = Baz.action([], %{}, %{}, %{private: %{}}, Router)
      [second, first] = conn.private.mazurka_invalidations
      assert Foo = first.resource
      assert %{"foo" => "123"} = first.params
      assert Bar = second.resource
      assert %{"bar" => "456"} = second.params
  end

  context "Option Passing" do
    defmodule Foo do
      use Mazurka.Resource

      param foo, option: true, condition: fn x ->
        {:ok, x}
      end

      # use input1 from Bar route
      input input1, option: true, default: "input1_default", condition: fn x ->
        {:ok, x}
      end

      # Bar doesn't send input2, so use default
      input input2, option: true, default: "input2_default", condition: fn x ->
        {:ok, x}
      end

      # use input1 from Bar route
      input input3, option: :input1, default: "input3_default", condition: fn x ->
        {:ok, x}
      end

      # use input1 from Bar route (foo doesn't exist)
      input input4, option: [:foo, :input1, :whatevs], default: "input4_default", condition: fn x ->
        {:ok, x}
      end


      mediatype Hyper do
        affordance do
          %{
            "foo" => foo <> "_aff",
            "input1" => input1 <> "_aff",
            "input2" => input2 <> "_aff",
            "input3" => input3 <> "_aff",
            "input4" => input4 <> "_aff"
          }
        end
        action do
          %{
            "foo" => foo <> "_action",
            "input1" => input1 <> "_action",
            "input2" => input2 <> "_action",
            "input3" => input3 <> "_action",
            "input4" => input4 <> "_action"
          }
        end
      end
    end

    defmodule Bar do
      use Mazurka.Resource

      mediatype Hyper do
        action do
          %{
            "bar" => link_to(Foo, %{foo: "newfoo"}, %{}, nil, %{input1: "input1_alt"})
          }
        end
      end
    end
    router Router do
      route "GET", ["foo", :foo], Foo
      route "GET", ["bar"], Bar
    end

    after
    "Foo.action" ->
      {res, _, _} = Foo.action([], %{"foo" => "foo"}, %{}, %{}, Router)
      assert %{
        "foo"  => "foo_action",
        "input1" => "input1_default_action",
        "input2" => "input2_default_action",
        "input3" => "input3_default_action",
        "input4" => "input4_default_action",
        "href" => "/foo/foo"
      } == res

    "Bar.action" ->
    {res, _, _} = Bar.action([], %{}, %{}, %{}, Router)

      assert %{
        "href" => "/bar",
        "bar" => %{
          "foo" => "newfoo_aff",
          "input1" => "input1_alt_aff",
          "input2" => "input2_default_aff",
          "input3" => "input1_alt_aff",
          "input4" => "input1_alt_aff",
          "href" => "/foo/newfoo"
          }
        } == res
  end


end
