print("Testing local by default")
a = 10
if _G.a == nil then 
    print("a is local") 
else 
    print("a is global") 
end

function f()
    b = 20
    if _G.b == nil then
        print("b is local")
    else
        print("b is global")
    end
end
f()

-- Test mixed
c, d = 30, 40
if _G.c == nil and _G.d == nil then
    print("c and d are local")
else
    print("c or d is global")
end
