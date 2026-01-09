-- Define a module table
prettyprint = {}

function bold(str)
    print("\27[1m" .. str .. "\27[0m")
end

function color(str, clr)
    
    color_dict = {
        white = "\27[0m",
        blue = "\27[34m",
        yellow = "\27[33m",
        red = "\27[31m",
        green = "\27[32m",
        purple = "\27[35m",
        orange = "\27[38;5;214m"
    }

    if color_dict[clr] then
        print(color_dict[clr] .. str .. color_dict["white"])
    else
        print(str) -- Default to no color if invalid color name is provided
    end
end

prettyprint.bold = bold
prettyprint.color = color

-- Export the module
return prettyprint
