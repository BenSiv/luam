-- bisection method for solving non-linear equations

delta=1e-6	-- tolerance

function bisect(f,a,b,fa,fb)
 c=(a+b)/2
 io.write(_.n," c=",c," a=",a," b=",b,"\n")
 if c==a or c==b or math.abs(a-b)<delta then return c,b-a end
 _.n=_.n+1
 fc=f(c)
 if fa*fc<0 then return bisect(f,a,c,fa,fc) else return bisect(f,c,b,fc,fb) end
end

-- find root of f in the inverval [a,b]. needs f(a)*f(b)<0
function solve(f,a,b)
 _.n=0
 z,e=bisect(f,a,b,f(a),f(b))
 io.write(string.format("after %d steps, root is %.17g with error %.1e, f=%.1e\n",_.n,z,e,f(z)))
end

-- our function
function f(x)
 return x*x*x-x-1
end

-- find zero in [1,2]
solve(f,1,2)
