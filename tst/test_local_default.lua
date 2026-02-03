_ = {}
print("esting local by default")
a = 10
if _.a == nil then 
    print("a is local") 
else 
    print("a is global") 
end

function f()
    b = 20
    if _.b == nil then
        print("b is local")
    else
        print("b is global")
    end
end
f()

-- est mixed
c, d = 30, 40
if _.c == nil and _.d == nil then
    print("c and d are local")
else
    print("c or d is global")
end
