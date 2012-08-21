module(..., package.seeall);

local tracked_table=require("tracked_table")

messages, subscriptions = {}, {}

local meta_weak_key = {__mode='k'}

--whether a given message satisfies a filter
local function satisfies(m, filter)
	local is_match=true
	for _, expr in ipairs(filter) do
		local ev_value = m[expr.attrib]
		if ev_value == nil then
			is_match=false
		else
			local op=expr.op
			local filt_value=expr.value
			local n_ev_value=tonumber(ev_value) or ev_value
			local n_filt_value=tonumber(filt_value) or filt_value

			if (op == '=' and (ev_value~=filt_value))
			or (op == '>' and (n_ev_value<=n_filt_value))
			or (op == '<' and (n_ev_value>=n_filt_value)) then
				is_match=false
			end
		end
		if not is_match then break end
	end
	return is_match
end


local function make_MessageTable ()
	local function make_MessageTable_MT ()
		local n = 0
		local own_table = tracked_table.make_TrackedTable()

		local MT={
			add=function(self, key, value)
				if not rawget(self, key) then
					n = n + 1
				end
				rawset(self, key, value)
				if value.own then own_table:add(key, value) end

				--initialize matching cache table
				local matches={}
				setmetatable(matches,meta_weak_key)
				value.matches=matches
				for sid, s in pairs(subscriptions) do
					if satisfies(value.message, s.filter) then
						--print ('M', sid, '+')
						matches[s] = true
					end 
				end
			end,
			del=function(self, key)
				if rawget(self, key) and n > 0 then
					n = n - 1
				end
				rawset(self, key, nil)
				own_table:del(key)
			end,
			len=function(self)
				return n
			end,
			own=function(self)
				return own_table
			end
		}
		MT.__index=MT
		return MT
	end
	return setmetatable(messages,make_MessageTable_MT())
end

local function make_SubscriptionTable ()
	local function make_SubscriptionsTable_MT ()
		local n = 0
		--local own_table = tracked_table.make_TrackedTable()

		local MT={
			add=function(self, key, value)
				if not rawget(self, key) then
					n = n + 1
				end
				rawset(self, key, value)
				--if value.own then own_table:add(key, value) end

				--update matching cache table in messages
				--print ('$$$$$', key)
				for mid,m in pairs(messages) do
					if satisfies(m.message, value.filter) then
						--print ('S', mid, '+')
						m.matches[value]=true
					else
						--print ('S', mid, '-')
						m.matches[value]=nil
					end
				end
			end,
			del=function(self, key)
				if rawget(self, key) and n > 0 then
					n = n - 1
				end
				rawset(self, key, nil)
				--own_table:del(key)
			end,
			len=function(self)
				return n
			end,
			--own=function(self)
			--	return own_table
			--end
		}
		MT.__index=MT
		return MT
	end
	return setmetatable(subscriptions,make_SubscriptionsTable_MT())
end

--[[
function get_m_s_tables()
	return messages, subscriptions
end
--]]

function init()
	subscriptions=make_SubscriptionTable()
	messages=make_MessageTable()
end

init()

--[[
T=make_TrackedTable()
T:add('one',{})
T:add('two',{})
T:add('three',{})

--T:del('two')

for a,b in pairs(T) do
	print(a, b)
end
print (T:len())
--]]

