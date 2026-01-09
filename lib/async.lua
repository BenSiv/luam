-- Async I/O utility for concurrent operations using lua-lanes
-- Provides a simple map_concurrent function for parallel I/O-bound tasks

async = {}

-- Check if lua-lanes is available
function has_lanes()
    ok, lanes = pcall(require, "lanes")
    return ok, lanes
end

-- Process items concurrently with a worker function
-- @param items: array of items to process
-- @param worker_fn: function(item) -> result
-- @param max_workers: max concurrent workers (default 10)
-- @param progress_fn: optional function(completed, total) called on each completion
-- @return: array of results in same order as items, whether concurrent was used
function async.map_concurrent(items, worker_fn, max_workers, progress_fn)
    max_workers = max_workers
    max_workers = max_workers or 10
    
    -- Check if lanes available and worth parallelizing
    ok, lanes = has_lanes()
    if not ok or #items <= 1 then
        -- Fallback to sequential processing
        results = {}
        for i, item in ipairs(items) do
            results[i] = worker_fn(item)
        end
        return results, false  -- false = not concurrent
    end
    
    -- Configure lanes
    lanes = lanes.configure()
    
    active = {}
    results = {}
    item_idx = 1
    completed = 0
    
    -- Process items with worker pool
    while completed < #items do
        -- Spawn new workers up to max
        while #active < max_workers and item_idx <= #items do
            idx = item_idx
            item = items[idx]
            
            -- Create lane worker
            worker = lanes.gen("*", worker_fn)(item)
            table.insert(active, {lane = worker, idx = idx})
            item_idx = item_idx + 1
        end
        
        -- Check and collect completed workers
        i = 1
        while i <= #active do
            lane_obj = active[i].lane
            status = lane_obj.status
            
            if status == "done" then
                -- Get result
                ok, result = pcall(function() return lane_obj[1] end)
                if ok then
                    results[active[i].idx] = result
                else
                    -- Lane succeeded but result retrieval failed
                    results[active[i].idx] = nil
                end
                completed = completed + 1
                
                -- Call progress callback if provided
                if progress_fn then
                    progress_fn(completed, #items)
                end
                
                table.remove(active, i)
            elseif status == "error" then
                -- Lane had an error
                err = lane_obj[0]
                print("Worker error: " .. tostring(err))
                results[active[i].idx] = nil
                completed = completed + 1
                
                -- Call progress callback if provided
                if progress_fn then
                    progress_fn(completed, #items)
                end
                
                table.remove(active, i)
            elseif status == "cancelled" or status == "killed" then
                -- Lane was terminated
                results[active[i].idx] = nil
                completed = completed + 1
                
                -- Call progress callback if provided
                if progress_fn then
                    progress_fn(completed, #items)
                end
                
                table.remove(active, i)
            else
                -- Still running, check next
                i = i + 1
            end
        end
        
        -- Small sleep to avoid busy waiting
        if #active >= max_workers then
            -- Wait a bit before checking again
            os.execute("sleep 0.01")
        end
    end
    
    return results, true  -- true = was concurrent
end

-- Export module
return async
