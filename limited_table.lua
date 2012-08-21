function make_LimitedTable (limit)
	local function make_LimitedTable_MT ()
		local n = 0
		local MT={
			add=function(self, key, value)
				if not rawget(self, key) then
					if n >= limit then
						self:removeOne()
					end
					n = n + 1
				end
				rawset(self, key, value)
			end,
			removeOne=function(self)
				self[next(self)]=nil
				n = n - 1
				--print('Removed entry')
			end,
			del=function(self, key)
				if rawget(self, key) and n > 0 then
					n = n - 1
				end
				rawset(self, key, nil)
			end,
			len=function(self)
				return n
			end
		}
		MT.__index=MT
		return MT
	end
	return setmetatable({},make_LimitedTable_MT())
end

--[[
T=make_LimitedTable(2)
T:add('one',{})
T:add('two',{})
T:add('three',{})

--T:del('two')

for a,b in pairs(T) do
	print(a, b)
end
--]]
