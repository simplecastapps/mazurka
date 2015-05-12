defmodule Mazurka.Compiler.Utils do
  # this is a pretty nasty hack since elixir can't just compile something without loading it
  def quoted_to_beam(ast, src) do
    fn(_) ->
      before = Code.compiler_options
      updated = Keyword.put(before, :ignore_module_conflict, :true)
      Code.compiler_options(updated)
      [{name, bin}] = Code.compile_quoted(ast, src)
      Code.compiler_options(before)
      maybe_reload(name)
      {name, bin}
    end
  end

  def is_target_stale?(path, version) when is_binary(path) do
    path
    |> String.to_char_list
    |> is_target_stale?(version)
  end
  def is_target_stale?(path, version) do
    case :beam_lib.version(path) do
      {:ok, {_, [prev | _]}} ->
        prev != version
      _error ->
        true
    end
  end

  defp maybe_reload(module) do
    case :code.which(module) do
      atom when is_atom(atom) ->
        # Module is likely in memory, we purge as an attempt to reload it
        :code.purge(module)
        :code.delete(module)
        Code.ensure_loaded?(module)
        :ok
      _file ->
        :ok
    end
  end
end