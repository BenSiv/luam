-- FASTA sequence reader, single-ID lookup, and writer.

bioinfo = {}

function read_fasta(filename)
    sequences = {}
    seq_id = nil
    seq = {}

    for line in io.lines(filename) do
        if string.starts_with(line, ">") then
            if seq_id != nil and seq_id != false then
                sequences[seq_id] = table.concat(seq)
            end
            seq_id = string.match(string.sub(line, 2), "%S+")
            seq = {}
        else
            table.insert(seq, line)
        end
    end

    if seq_id != nil and seq_id != false then
        sequences[seq_id] = table.concat(seq)
    end

    return sequences
end

function query_fasta(filename, target_id)
    seq_id = nil
    seq = {}

    for line in io.lines(filename) do
        if string.starts_with(line, ">") then
            if seq_id == target_id then
                return table.concat(seq)
            end
            seq_id = string.match(string.sub(line, 2), "%S+")
            seq = {}
        elseif seq_id == target_id then
            table.insert(seq, line)
        end
    end

    if seq_id == target_id then
        return table.concat(seq)
    end

    return nil
end

function write_fasta(filename, data)
    file, err = io.open(filename, "w")
    if file == nil then
        error("Could not open file for writing: " .. tostring(err))
    end

    for _, entry in ipairs(data) do
        io.write(file, ">" .. entry.name .. "\n")
        seq = entry.seq
        for i = 1, #seq, 60 do
            io.write(file, string.sub(seq, i, i + 59) .. "\n")
        end
    end

    io.close(file)
end

bioinfo.read_fasta = read_fasta
bioinfo.query_fasta = query_fasta
bioinfo.write_fasta = write_fasta

return bioinfo
