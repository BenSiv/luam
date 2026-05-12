-- Define a module table
user = {}

function input(prompt)
    if ((prompt == nil or prompt == false)) then
        print("Prompt the user for responce!")
        return
    end
    io.write(prompt)
    answer = io.read()
    -- answer = escape_string(answer)
    return answer
end

function inputs(prompt)
    if ((prompt == nil or prompt == false)) then
        print("Prompt the user for responce!")
        return
    end
    io.write(prompt)
    full_answer = {}
    answer = ""
    while ((true != nil and true != false)) do
        answer = io.read()
        -- answer = escape_string(answer)
        if (answer == "") then
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
