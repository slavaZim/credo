defmodule Credo.Check.Warning.NameRedeclarationByFn do
  @moduledoc """
  Names assigned to parameters of an anonymous function should not be the
  same as names of functions in the same module or in `Kernel`.

  Example:

      def handle_something(time_list) do
        time_list
        |> Enum.each(fn(time) ->   # not clear if talking about time/0 or time
            IO.puts time
          end)
      end

      def time do
        TimeHelper.now
      end

  This might not seem like a big deal, especially for small functions.
  But there is no downside to avoiding it, especially in the case of functions
  with arity `/0` and Kernel functions.

  True story: You might pattern match on a parameter geniusly called `node`.
  Then you remove that match for some reason and rename the parameter to `_node`
  because it is no longer used.
  Later you reintroduce the pattern match on `node` but forget to also rename
  `_node` and suddenly the match is actually against `Kernel.node/0` and has the
  weirdest side effects.

  This happens. I mean, to a friend of mine, it did. Who ... later told me.
  """

  @explanation [check: @moduledoc]
  @kernel_fun_names [
    :make_ref,
    :node,
    :self
  ]
  @kernel_macro_names [
  ]
  @excluded_names [:_, :sigil_r, :sigil_R]

  alias Credo.Code.Module

  use Credo.Check, base_priority: :high

  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.Code.traverse(&traverse(&1, &2, issue_meta, @excluded_names))
    |> List.flatten
    |> Enum.reject(&is_nil/1)
  end

  defp traverse({:defmodule, _, _} = ast, issues, issue_meta, excluded_names) do
    def_names = Module.def_names_with_op(ast, 0)
    issues =
      issues ++ Credo.Code.traverse(ast, &mod_traverse(&1, &2, issue_meta, def_names, excluded_names))
    {ast, issues}
  end
  defp traverse(ast, issues, _issue_meta, _excluded_names) do
    {ast, issues}
  end

  defp mod_traverse({:fn, _meta, lhs} = ast, issues, issue_meta, def_names, excluded_names) do
    case find_issue(lhs, issue_meta, def_names, excluded_names) do
      nil -> {ast, issues}
      list when is_list(list) -> {ast, issues ++ list}
      new_issue -> {ast, issues ++ [new_issue]}
    end
  end
  defp mod_traverse(ast, issues, _issue_meta, _def_names, _excluded_names) do
    {ast, issues}
  end



  def find_issue({:->, _meta2, [lhs, _rhs]}, issue_meta, def_names, excluded_names) do
    find_issue(lhs, issue_meta, def_names, excluded_names)
  end
  def find_issue({:%{}, _meta2, keywords}, issue_meta, def_names, excluded_names) do
    keywords
    |> Enum.map(fn
      {_lhs, rhs} ->
        find_issue(rhs, issue_meta, def_names, excluded_names)
      _ ->
        nil
      end)
  end
  def find_issue({:{}, _meta2, tuple_list}, issue_meta, def_names, excluded_names) do
    find_issue(tuple_list, issue_meta, def_names, excluded_names)
  end
  def find_issue({:%, _meta, [{:__aliases__, _meta1, _mod}, map]}, issue_meta, def_names, excluded_names) do
    find_issue(map, issue_meta, def_names, excluded_names)
  end
  def find_issue({name, meta, _}, issue_meta, def_names, excluded_names) do
    def_name_with_op =
      def_names
      |> Enum.find(fn({def_name, _op}) -> def_name == name end)
    cond do
      excluded_names |> Enum.member?(name) ->
        nil
      def_name_with_op ->
        what =
          case def_name_with_op do
            {_, :def} -> "a function in the same module"
            {_, :defp} -> "a private function in the same module"
            {_, :defmacro} -> "a macro in the same module"
            _ -> "ERROR"
          end
        issue_for(issue_meta, meta[:line], name, what)
      @kernel_fun_names |> Enum.member?(name) ->
        issue_for(issue_meta, meta[:line], name, "the `Kernel.#{name}` function")
      @kernel_macro_names |> Enum.member?(name) ->
        issue_for(issue_meta, meta[:line], name, "the `Kernel.#{name}` macro")
      true ->
        nil
    end
  end
  def find_issue(list, issue_meta, def_names, excluded_names) when is_list(list) do
    list
    |> Enum.map(&find_issue(&1, issue_meta, def_names, excluded_names))
  end
  def find_issue(tuple, issue_meta, def_names, excluded_names) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list
    |> Enum.map(&find_issue(&1, issue_meta, def_names, excluded_names))
  end
  def find_issue(_, _, _, _) do
    nil
  end

  defp issue_for(issue_meta, line_no, trigger, what) do
    format_issue issue_meta,
      message: "Parameter `#{trigger}` has same name as #{what}.",
      trigger: trigger,
      line_no: line_no
  end
end
