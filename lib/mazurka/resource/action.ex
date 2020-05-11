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
        Mazurka.Resource.Utils.Scope.dump()
        var!(conn) = unquote(Utils.conn)
        action = unquote(block)
        res = unquote(mediatype).handle_action(action)
        unquote(Utils.conn) = var!(conn)
        __mazurka_event__(res, unquote_splicing(Utils.arguments), unquote(Utils.scope), unquote(Utils.mediatype))
      end
    end
  end

  defmacro __before_compile__(_) do
    quote location: :keep do
      def action(content_type = {_, _, _}, unquote_splicing(Utils.arguments)) do
        case __mazurka_provide_content_type__(content_type) do
          nil ->
            raise Mazurka.UnacceptableContentTypeException, [
              content_type: content_type,
              acceptable: __mazurka_acceptable_content_types__(),
              conn: unquote(Utils.conn)
            ]
          mediatype ->
            case __mazurka_check_params__(unquote(Utils.params)) do
              {[], []} ->
                scope = __mazurka_scope__(mediatype, unquote_splicing(Utils.arguments)) |> IO.inspect(label: "scope_action")
                case __mazurka_conditions__(0, unquote_splicing(Utils.arguments), scope) do
                  {:error, %{:__struct__ => _} = exception} ->
                    raise exception
                  {:error, message} ->
                    raise Mazurka.ConditionException, message: message, conn: unquote(Utils.conn)
                  :ok ->
                    case __mazurka_validations__(0, unquote_splicing(Utils.arguments), scope) do
                      {:error, message} ->
                        raise Mazurka.ValidationException, message: message, conn: unquote(Utils.conn)
                      :ok ->
                        __mazurka_match_action__(mediatype, unquote_splicing(Utils.arguments), scope)
                    end
                end
              {missing, nil_params} ->
                raise Mazurka.MissingParametersException, params: missing ++ nil_params, conn: unquote(Utils.conn)
            end
        end
      end

      defp __mazurka_match_action__(_, unquote_splicing(Utils.arguments), _) do
        ## TODO raise exception
        nil
      end
    end
  end
end
