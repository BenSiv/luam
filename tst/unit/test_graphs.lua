
graphs = require("graphs")

print("esting graphs...")

data = {
    {source="", name="B"}, --  -> B
    {source="B", name="C"}  -- B -> C
}
g, map = graphs.build_graph(data)

--  is root?
--  -> B -> C.
-- oots: .
roots = graphs.get_roots(g, map)
assert(roots[1] == "", "get_roots failed")

print("graphs tests passed")
