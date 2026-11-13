-- Define a module table
prettyprint = {}

function bold(str)
    print("\x1B[1m" .. str .. "\x1B[0m")
end

function color(str, clr)
    
    color_dict = {
        white = "\x1B[0m",
        blue = "\x1B[34m",
        yellow = "\x1B[33m",
        red = "\x1B[31m",
        green = "\x1B[32m",
        purple = "\x1B[35m",
        orange = "\x1B[38;5;214m"
    }

    if ((color_dict[clr] != nil and color_dict[clr] != false)) then
        print(color_dict[clr] .. str .. color_dict["white"])
    else
        print(str) -- Default to no color if invalid color name is provided
    end
end

prettyprint.bold = bold
prettyprint.color = color

-- Export the module
return prettyprint
