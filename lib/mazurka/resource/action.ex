defmodule Mazurka.Resource.Action do
  @moduledoc false

  alias Mazurka.Resource.Utils

  defmacro __using__(_) do
    quote do
      @doc """
      Create an action block

          mediatype #{inspect(__MODULE__)} do
            action do
              # action goes here
            end
          end
      """

      defmacro action(block) do
        mediatype = __MODULE__
        quote do
          require Mazurka.Resource.Action
          Mazurka.Resource.Action.action(unquote(mediatype), unquote(block))
        end
      end
    end
  end

  @doc """
  Create an action block for a mediatype

      action Mazurka.Mediatype.MyCustomMediatype do
        # action goes here
      end
  """

  defmacro action(mediatype, [do: block]) do
    quote do
      defp __mazurka_match_action__(unquote(mediatype) = unquote(Utils.mediatype), unquote_splicing(Utils.arguments), unquote(Utils.scope)) do

        Mazurka.Resource.Utils.Scope.dump(:action)
        var!(conn) = unquote(Utils.conn)
        action = unquote(block)
        res = unquote(mediatype).handle_action(action)
        unquote(Utils.conn) = var!(conn)
        {res, var!(conn)}
      end
    end
  end

  defmacro __before_compile__(_) do
    quote do
      def action(content_type = {_, _, _}, unquote_splicing(Utils.arguments)) do
        case __mazurka_provide_content_type__(content_type) do
          nil ->
            raise Mazurka.UnacceptableContentTypeException, [
              content_type: content_type,
              acceptable: __mazurka_acceptable_content_types__(),
              conn: unquote(Utils.conn)
            ]
          mediatype ->
            unquote(Utils.params) = __mazurka_filter_params__(unquote(Utils.params))
            unquote(Utils.input) = __mazurka_filter_inputs__(unquote(Utils.input))
            case __mazurka_check_params__(unquote(Utils.params)) do
              {[], []} ->
                case __mazurka_action_scope_check__(mediatype, unquote_splicing(Utils.arguments)) do
                  {:no_error, scope} ->
                    __mazurka_match_action__(mediatype, unquote_splicing(Utils.arguments), scope)
                  {{:validation, error_message}, _} ->
                    raise Mazurka.ValidationException, message: error_message, conn: unquote(Utils.conn)
                  {{:condition, error_message}, _} = x ->
                    raise Mazurka.ConditionException, message: error_message, conn: unquote(Utils.conn)
                end
              {missing, nil_params} ->
                raise Mazurka.MissingParametersException, params: missing ++ nil_params, conn: unquote(Utils.conn)
            end
        end
      end

      defp __mazurka_match_action__(m, unquote_splicing(Utils.arguments), s) do
        ## TODO raise exception
        nil
      end
    end
  end
end
