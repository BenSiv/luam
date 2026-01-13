utils = require("utils")

-- Define a module table
bioinfo = {}

function read_fasta(filename)
    sequences = {}
    seq_id = nil
    seq = {}

    for line in io.lines(filename) do
        if utils.starts_with(line, ">") then
            -- Save the previous sequence if it exists
            if seq_id then
                sequences[seq_id] = table.concat(seq)
            end
            -- Start a new sequence
            seq_id = utils.match(utils.slice(line, 2), "%S+")  -- Remove ">" and take first word as ID
            seq = {}  -- Reset sequence storage
        else
            table.insert(seq, line)
        end
    end

    -- Save the last sequence
    if seq_id then
        sequences[seq_id] = table.concat(seq)
    end

    return sequences
end

function query_fasta(filename, target_id)
    seq_id = nil
    seq = {}

    for line in io.lines(filename) do
        if utils.starts_with(line, ">") then
            if seq_id == target_id then
                return table.concat(seq)
            end
            seq_id = utils.match(utils.slice(line, 2), "%S+")  -- Remove ">" and take first word as ID
            seq = {}  -- Reset sequence storage
        elseif seq_id == target_id then
            table.insert(seq, line)
        end
    end

    -- Return the last sequence if it was the target
    if seq_id == target_id then
        return table.concat(seq)
    end

    return nil  -- Sequence not found
end

function write_fasta(filename, data)
    file, err = io.open(filename, "w")
    if not is file then
        error("Could not open file for writing: " .. err)
    end

    for _, entry in ipairs(data) do
        file.write(file, ">" .. entry.name .. "\n")
        -- Wrap sequence at 60 characters per line (FASTA convention)
        seq = entry.seq
        for i = 1, #seq, 60 do
            file.write(file, seq.sub(seq, i, i+59) .. "\n")
        end
    end

    file.close(file)
end

bioinfo.read_fasta = read_fasta
bioinfo.query_fasta = query_fasta
bioinfo.write_fasta = write_fasta

-- Export the module
return bioinfo
