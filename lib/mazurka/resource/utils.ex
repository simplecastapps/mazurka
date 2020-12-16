defmodule Mazurka.Resource.Utils do
  @moduledoc false

  def arguments do
    [params(), input(), conn(), router(), opts()]
  end

  def router do
    {:'$mazurka_router', [warn: false], __MODULE__}
  end

  def params do
    {:'$mazurka_params', [warn: false], __MODULE__}
  end

  def input do
    {:'$mazurka_input', [warn: false], __MODULE__}
  end

  def conn do
    {:'$mazurka_conn', [warn: false], __MODULE__}
  end

  def opts do
    {:'$mazurka_opts', [warn: false], __MODULE__}
  end

  def mediatype do
    {:'$mazurka_mediatype', [warn: false], __MODULE__}
  end

  def scope do
    {:'$mazurka_scope', [warn: false], __MODULE__}
  end

  def all(type) do
    case type do
      :input ->
        {:'$mazurka_all_input', [warn: false], __MODULE__}
      :params ->
        {:'$mazurka_all_params', [warn: false], __MODULE__}
    end
  end

  # Just to hide a variable that needs to exist, but we would
  # prefer was not referenced.
  def hidden_var(name) do
    {:"$mazurka_hidden_#{name}", [warn: false], __MODULE__}
  end
end
