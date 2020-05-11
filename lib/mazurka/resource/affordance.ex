defmodule Mazurka.Resource.Affordance do
  @moduledoc false

  alias Mazurka.Resource.Utils

  defmacro __using__(_) do
    quote do
      @doc """
      Create an affordance block

          mediatype #{inspect(__MODULE__)} do
            affordance do
              # affordance goes here
            end
          end
      """

      defmacro affordance(block) do
        mediatype = __MODULE__
        quote do
          require Mazurka.Resource.Affordance
          Mazurka.Resource.Affordance.affordance(unquote(mediatype), unquote(block))
        end
      end
    end
  end

  @doc """
  Create an affordance block for a mediatype

      affordance Mazurka.Mediatype.MyCustomMediatype do
        # affordance goes here
      end
  """

  defmacro affordance(mediatype, [do: block]) do
    quote location: :keep do
      defp __mazurka_match_affordance__(unquote(mediatype) = unquote(Utils.mediatype), unquote_splicing(Utils.arguments), unquote(Utils.scope)) do
        Mazurka.Resource.Utils.Scope.dump()
        var!(conn) = unquote(Utils.conn())
        affordance = rel_self()
        props = unquote(block)
        unquote(Utils.conn()) = var!(conn)
        unquote(mediatype).handle_affordance(affordance, props)
      end
    end
  end

  defmacro __before_compile__(_) do
    quote location: :keep do
      def affordance(content_type = {_, _, _}, unquote_splicing(Utils.arguments)) do
        case __mazurka_provide_content_type__(content_type) do
          nil ->
            %Mazurka.Affordance.Unacceptable{resource: __MODULE__,
                                             params: unquote(Utils.params),
                                             input: unquote(Utils.input),
                                             opts: unquote(Utils.opts)}
          mediatype ->
            affordance(mediatype, unquote_splicing(Utils.arguments))
        end
      end

      def affordance(mediatype, unquote_splicing(Utils.arguments)) when is_atom(mediatype) do
        case __mazurka_check_params__(unquote(Utils.params)) do
          {[], []} ->
            __mazurka_evaluate_affordance__(unquote_splicing(Utils.arguments)) |> case do
             {:error, err} ->
               %Mazurka.Affordance.Undefined{
                 resource: __MODULE__,
                 mediatype: mediatype,
                 params: unquote(Utils.params),
                 input: unquote(Utils.input),
                 opts: unquote(Utils.opts)
               }
             {:ok, scope} ->
               __mazurka_match_affordance__(mediatype, unquote_splicing(Utils.arguments), scope)
            end

          {[   _ | _] = missing, _} ->
            raise Mazurka.MissingParametersException, params: missing, conn: unquote(Utils.conn())
           _   ->
            %Mazurka.Affordance.Undefined{
              resource: __MODULE__,
              mediatype: mediatype,
              params: unquote(Utils.params),
              input: unquote(Utils.input),
              opts: unquote(Utils.opts)}
        end
      end

      defp __mazurka_match_affordance__(mediatype, unquote_splicing(Utils.arguments), scope) do
        __mazurka_default_affordance__(mediatype, unquote_splicing(Utils.arguments), scope)
      end
    end
  end
end
