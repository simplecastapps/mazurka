defmodule Mazurka.Compiler.Etude do
  alias Mazurka.Compiler.Utils
  alias Etude.Node

  def elixir_to_etude(ast, env) do
    ## TODO prewalk and check for defined functions
    {etude_ast, _acc} = Macro.postwalk(ast, [], &(handle_node(&1, &2, env)))
    etude_ast
  end

  # alias
  defp handle_node({:__aliases__, _, _} = path, acc, env) do
    {Utils.eval(path, env), acc}
  end
  # bif
  defp handle_node({:=, meta, [lhs, rhs]}, acc, _env) do
    {%Node.Assign{name: lhs,
                  expression: rhs,
                  line: meta[:line]}, acc}
  end
  defp handle_node({:==, meta, [lhs, rhs]}, acc, _env) do
    {%Node.Call{module: Kernel,
                function: :==,
                arguments: [lhs, rhs],
                attrs: %{native: true},
                line: meta[:line]}, acc}
  end
  defp handle_node({:^, _, [%Node.Call{attrs: attrs} = call]}, acc, _env) do
    attrs = Dict.put(attrs, :native, true)
    {%{call | attrs: attrs}, acc}
  end
  defp handle_node({:_, meta, _}, acc, _env) do
    {%Node.Var{name: :_,
               line: meta[:line]}, acc}
  end
  # TODO add support in etude
  # defp handle_node({:->, meta, [[lhs], rhs]}, acc, _env) do
  #   {{Clause, lhs, rhs}, acc}
  # end
  # defp handle_node({:case, meta, [expression, body]}, acc, _env) do
  #   {{Case, expression, body}, acc}
  # end
  defp handle_node({:if, meta, [expression, [arm]]}, acc, _env) do
    {%Node.Cond{expression: expression,
                arms: [arm],
                line: meta[:line]}, acc}
  end
  defp handle_node({:if, meta, [expression, [arm1, {:else, arm2}]]}, acc, _env) do
    {%Node.Cond{expression: expression,
                arms: [arm1, arm2],
                line: meta[:line]}, acc}
  end
  # atom
  defp handle_node(atom, acc, _env) when is_atom(atom) do
    {atom, acc}
  end
  # binary
  defp handle_node(binary, acc, _env) when is_binary(binary) do
    {binary, acc}
  end
  # block
  defp handle_node({:__block__, meta, block}, acc, _env) do
    {%Node.Block{children: block,
                 line: meta[:line]}, acc}
  end
  # call
  defp handle_node({:., meta, [module, fun]}, acc, _env) do
    {%Node.Call{module: module,
                function: fun,
                line: meta[:line]}, acc}
  end
  defp handle_node({%Node.Call{} = call, _, args}, acc, _env) do
    {%{call | arguments: args}, acc}
  end
  # do
  defp handle_node({:do, child}, acc, _env) do
    {child, acc}
  end
  # list
  defp handle_node(list, acc, _env) when is_list(list) do
    {list, acc}
  end
  # map
  defp handle_node({:%{}, _, kvs}, acc, _env) do
    {:maps.from_list(kvs), acc}
  end
  # map key
  defp handle_node({:&&&, meta, [lhs, rhs]}, acc, _env) do
    {%Node.Cond{expression: lhs,
                arms: [rhs],
                line: meta[:line]}, acc}
  end
  # map key/value
  defp handle_node({k, v}, acc, _env) do
    {{k, v}, acc}
  end
  # numbers
  defp handle_node(number, acc, _env) when is_integer(number) or is_float(number) do
    {number, acc}
  end
  # struct
  defp handle_node({:%, meta, [module, props]}, acc, _env) do
    props = :maps.to_list(props)
    {%Node.Call{module: Kernel,
                function: :struct,
                arguments: [module, props],
                attrs: %{native: true},
                line: meta[:line]}, acc}
  end
  # variable
  defp handle_node({name, meta, nil}, acc, _env) when is_atom(name) do
    {%Node.Var{name: name,
               line: meta[:line]}, acc}
  end

  # local call (needs to be last)
  defp handle_node({name, meta, args}, acc, _env) when is_atom(name) and is_list(args) do
    {%Node.Call{module: :__MODULE__,
                function: name,
                arguments: args,
                line: meta[:line]}, acc}
  end
end