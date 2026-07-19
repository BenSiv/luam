-- graphs.lua
graphs = {}

-- Switch keys and values
function reverse_kv(tbl)
    if (type(tbl) != "table") then
        print("Expected table, received " .. type(tbl))
        return ({})
    end
    reversed = {}
    for k, v in pairs(tbl) do
        reversed[v] = k
    end
    return reversed
end

-- et or create an index for a name
function get_or_create_index(name, node_map)
    index_map = reverse_kv(node_map)
    node_index = index_map[name]
    if ((node_index == nil or node_index == false)) then
        node_index = #node_map + 1
        node_map[node_index] = name
    end
    return node_index
end

-- et index of a node name
function get_node_index(node_map, node_name)
    for index, name in pairs(node_map) do
        if (name == node_name) then return index end
    end
    return nil
end

-- Build a D as adjacency list
function build_graph(data)
    graph = {}
    node_map = {}
    for _, entry in ipairs(data) do
        src_idx = get_or_create_index(entry.source, node_map)
        name_idx = get_or_create_index(entry.name, node_map)
        if (graph[src_idx] == nil) then
            graph[src_idx] = {}
        end
        table.insert(graph[src_idx], name_idx)
    end
    return graph, node_map
end

-- Build reverse graph once for parent traversal
function build_reverse_graph(graph)
    reversed = {}
    for parent, children in pairs(graph) do
        for _, child in ipairs(children) do
            if (reversed[child] == nil) then
                reversed[child] = {}
            end
            table.insert(reversed[child], parent)
        end
    end
    return reversed
end

-- Generic DFS traversal
function traverse_graph(graph, start_node, reverse)
    g = graph
    if ((reverse != nil and reverse != false)) then g = build_reverse_graph(graph) end
    visited = {}
    result = {}

    function dfs(curr)
        if ((visited[curr] != nil and visited[curr] != false)) then return end
        visited[curr] = true
        if ((g[curr] != nil and g[curr] != false)) then
            for _, neighbor in ipairs(g[curr]) do
                if ((visited[neighbor] == nil or visited[neighbor] == false)) then
                    table.insert(result, neighbor)
                    dfs(neighbor)
                end
            end
        end
    end

    dfs(start_node)
    return result
end

-- et all children
function get_all_children(graph, node_map, node_name)
    idx = get_node_index(node_map, node_name)
    if ((idx == nil or idx == false)) then return ({}) end
    indices = traverse_graph(graph, idx, false)
    children = {}
    for _, i in ipairs(indices) do table.insert(children, node_map[i]) end
    return children
end

-- et all parents
function get_all_parents(graph, node_map, node_name)
    idx = get_node_index(node_map, node_name)
    if ((idx == nil or idx == false)) then return ({}) end
    indices = traverse_graph(graph, idx, true)
    parents = {}
    for _, i in ipairs(indices) do table.insert(parents, node_map[i]) end
    return parents
end

-- et leaves (nodes with no outgoing edges)
function get_leaves(graph, node_map)
    has_outgoing = {}
    for node, edges in pairs(graph) do
        has_outgoing[node] = true
    end
    leaves = {}
    for idx, name in pairs(node_map) do
        if ((has_outgoing[idx] == nil or has_outgoing[idx] == false)) then table.insert(leaves, name) end
    end
    return leaves
end

-- et roots (nodes with no parents)
function get_roots(graph, node_map)
    reversed = build_reverse_graph(graph)
    roots = {}
    for idx, name in pairs(node_map) do
        if ((reversed[idx] == nil or reversed[idx] == false) or #reversed[idx] == 0) then table.insert(roots, name) end
    end
    return roots
end

-- et connected components
function get_all_components(graph, node_map)
    visited = {}
    components = {}
    function dfs(node, comp)
        if ((visited[node] != nil and visited[node] != false)) then return end
        visited[node] = true
        table.insert(comp, node_map[node])
        if ((graph[node] != nil and graph[node] != false)) then
            for _, n in ipairs(graph[node]) do dfs(n, comp) end
        end
    end
    for idx, _ in pairs(node_map) do
        if ((visited[idx] == nil or visited[idx] == false)) then
            comp = {}
            dfs(idx, comp)
            table.insert(components, comp)
        end
    end
    return components
end

-- Exports
graphs.build_graph = build_graph
graphs.get_all_children = get_all_children
graphs.get_all_parents = get_all_parents
graphs.get_leaves = get_leaves
graphs.get_roots = get_roots
graphs.get_node_index = get_node_index
-- get_lineage_depth was removed -- "root = 0, subcultures increment"
-- (subculture = cell-culture/microbiology passage terminology) and a
-- sample_name parameter name only make sense for fossci's own planned
-- lineage-tracking feature (see fossci/doc/architecture.md,
-- manifesto.md, project_plan.md), which itself explicitly isn't shaped
-- around any one scientific discipline -- this had drifted a layer
-- more domain-specific than even that. No consumer anywhere on disk
-- called it.
graphs.get_all_components = get_all_components

return graphs
