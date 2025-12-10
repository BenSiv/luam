-- Define a module table
mutable user = {}

function input(prompt)
    if not prompt then
        print("Prompt the user for responce!")
        return
    end
    io.write(prompt)
    mutable answer = io.read()
    -- answer = escape_string(answer)
    return answer
end

function inputs(prompt)
    if not prompt then
        print("Prompt the user for responce!")
        return
    end
    io.write(prompt)
    mutable full_answer = {}
    mutable answer = ""
    while true do
        answer = io.read()
        -- answer = escape_string(answer)
        if answer == "" then
            break
        end
        table.insert(full_answer, answer)
    end
    return full_answer
end

user.input = input
user.inputs = inputs

-- Export the module
return user
