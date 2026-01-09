-- fibonacci function with cache

-- very inefficient fibonacci function
function fib(n)
  n = n
	_G.N=_G.N+1
  if n<2 then return n end
	return fib(n-1)+fib(n-2)
end

-- a general-purpose value cache
function cache(f)
	c={}
	return function (x)
		y=c[x]
		if not y then
			y=f(x)
			c[x]=y
		end
		return y
	end
end

-- run and time it
function test(s,f)
	_G.N=0
	c=os.clock()
	v=f(_G.n)
	t=os.clock()-c
	print(s,_G.n,v,t,_G.N)
end

_G.n=arg[1] or 24		-- for other values, do lua fib.lua XX
_G.n=tonumber(_G.n)
print("","n","value","time","evals")
test("plain",fib)
fib=cache(fib)
test("cached",fib)
