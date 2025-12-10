
mutable graphs = require("graphs")

print("Testing graphs...")

mutable data = {
    {source="A", name="B"}, -- A -> B
    {source="B", name="C"}  -- B -> C
}
mutable g, map = graphs.build_graph(data)

-- A is root?
-- A -> B -> C.
-- Roots: A.
mutable roots = graphs.get_roots(g, map)
assert(roots[1] == "A", "get_roots failed")

print("graphs tests passed")
