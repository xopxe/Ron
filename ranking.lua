module(..., package.seeall);

local configuration = require("configuration")
local socket = require("socket")

local function mesage_quality(m)
	local q = 0
	--accumulated quality for a message
	for s,_ in pairs(m.matches) do
		if not s.own then --don't accumulate quality from our own subs
			q = q+s.p_encounter 
		end
	end
	return q
end

local function find_worsts(messages)
	local worst_id, worst_q, worsts
	for mid, m in pairs(messages) do
		if not m.own then
			local q = mesage_quality(m)
			if not worst_q or q<worst_q then
				worst_id, worst_q = mid, q
				worsts = {}
			end
			if q == worst_q then
				worsts[#worsts+1]=mid --keep a list of entries p==min.
			end
			--if worst_p==0 then break end
		end
	end
	return worsts, worst_q
end

function find_replaceable_homogeneous (messages)
	local ownmessages=messages:own()
	local now = socket.gettime()

	if ownmessages:len() < configuration.reserved_owns then
		--guarantee for owns satisfied. find replacement between not owns

		local worsts, worst_q=find_worsts(messages)

		local number_of_ranges = configuration.number_of_ranges
		local ranking_window = configuration.ranking_window
		local range_count={}
		for i=1,number_of_ranges do range_count[i] = {} end
		--classify in ranges
		for _, mid in ipairs(worsts) do
			local m = messages[mid]
			local age=(now-m.ts) + m.message._in_transit --estimated emission time
			if age > ranking_window then return mid end
			local range = math.floor(number_of_ranges * (age / ranking_window))+1
			if range > number_of_ranges then range = number_of_ranges end 
			local rangelist = range_count[range]
			rangelist[#rangelist+1] = mid
		end
		--find longest range
		local longest_range, longest_range_i
		for i=1, number_of_ranges do 
			local count = #(range_count[i])
			if not longest_range_i or count > longest_range then
				longest_range_i, longest_range = i, count
			end		
		end
		--in longest range find most seen
		local max_seen, max_seen_mid
		for _, mid in ipairs(range_count[longest_range_i]) do
			local m = messages[mid]
			local seen = m.seen
			if not m.own and (not max_seen_mid or max_seen < seen) then
				max_seen_mid, max_seen = mid, seen
			end
		end
		
		return max_seen_mid
	else --ownmessages:len() >= configuration.reserved_owns
		--too much owns. find oldest registered own 
		local min_ts, min_ts_mid
		for mid, m in pairs(ownmessages) do
			if not min_ts_mid or min_ts > m.ts then
				min_ts_mid, min_ts = mid, m.ts
			end
		end

		return min_ts_mid
	end	
end

function find_replaceable_seen_rate (messages)
	local ownmessages=messages:own()
	local now = socket.gettime()

	if ownmessages:len() < configuration.reserved_owns then
		--guarantee for owns satisfied. find replacement between not owns

		local worsts, worst_q=find_worsts(messages)

		--between the worst, find most seen
		local max_seenrate, max_seenrate_mid
		for _, mid in ipairs(worsts) do
			local m = messages[mid]
			local age = now - m.ts
			local seenrate = m.seen / age
			if not m.own and age > configuration.min_time_for_averaging
			and (not max_seenrate_mid or max_seenrate < seenrate) then
				max_seenrate_mid, max_seenrate = mid, seenrate
			end
		end
		
		return max_seenrate_mid
	else --ownmessages:len() >= configuration.reserved_owns
		--too much owns. find oldest registered own 
		local min_ts, min_ts_mid
		for mid, m in pairs(ownmessages) do
			if not min_ts_mid or min_ts > m.ts then
				min_ts_mid, min_ts = mid, m.ts
			end
		end

		return min_ts_mid
	end	
end

function find_replaceable_seen (messages)
	local ownmessages=messages:own()
	local now = socket.gettime()

	if ownmessages:len() < configuration.reserved_owns then
		--guarantee for owns satisfied. find replacement between not owns

		local worsts, worst_q=find_worsts(messages)

		--between the worst, find most seen
		local max_seen, max_seen_mid
		for _, mid in ipairs(worsts) do
			local m = messages[mid]
			local seen = m.seen
			if not m.own and (not max_seen_mid or max_seen < seen) then
				max_seen_mid, max_seen = mid, seen
			end
		end
		
		return max_seen_mid
	else --ownmessages:len() >= configuration.reserved_owns
		--too much owns. find oldest registered own 
		local min_ts, min_ts_mid
		for mid, m in pairs(ownmessages) do
			if not min_ts_mid or min_ts > m.ts then
				min_ts_mid, min_ts = mid, m.ts
			end
		end

		return min_ts_mid
	end	
end

function find_replaceable_diversity_array (messages)
	local ownmessages=messages:own()

	if ownmessages:len() < configuration.reserved_owns then
		--guarantee for owns satisfied. find replacement between not owns

		local worsts, worst_q=find_worsts(messages)
		--configuration.log('looking for a replacement', #worsts, worst_q)
		
		local diversity_array = {}

		--between the worst, find the oldest
		local min_ts, min_ts_mid
		for _, mid in ipairs(worsts) do
			local m = messages[mid]
			if m.discard_sample then
				diversity_array[#diversity_array + 1] = mid
			end
			--configuration.log('$$$$', min_ts_mid, min_ts, m.ts, m.message._in_transit )
			local em=m.ts - m.message._in_transit --estimated emission time
			--configuration.log('looking for a replacement ---- ', mid, em)
			--local em=-m.emited
			--local em=m.message.notification_id
			if not m.own 
			and (not min_ts_mid or min_ts > em) 
			and m.emited > configuration.min_n_broadcasts 
			and not m.discard_sample then
				min_ts_mid, min_ts = mid, em
			end
		end
		
		if min_ts_mid and math.random() <= configuration.diversity_survival_quotient then
			messages[min_ts_mid].discard_sample = true
			if #diversity_array > configuration.max_size_diversity_array then				
				min_ts_mid = diversity_array[math.random(#diversity_array)]
				configuration.log("Diversity array full. Replacing.")
			else
				min_ts_mid = nil
				configuration.log("Populating diversity array.")
			end
		end
		
		return min_ts_mid
	else --ownmessages:len() >= configuration.reserved_owns
		--too much owns. find oldest registered own 
		local min_ts, min_ts_mid
		for mid, m in pairs(ownmessages) do
			if not min_ts_mid or min_ts > m.ts then
				min_ts_mid, min_ts = mid, m.ts
			end
		end

		return min_ts_mid
	end

end

local myname_hash

-- 
local function string_hash (str)
	local temp_hash = 0
	for i = 1, #str do
		temp_hash = temp_hash + string.byte(str, i)
	end
	return temp_hash
end

local function aging_hash (mid)
	myname_hash = myname_hash or string_hash(configuration.my_name)
	local temp_hash = myname_hash + string_hash(mid)

	return (math.fmod(temp_hash,100) * ((1 - configuration.max_aging_slower) / 100) ) + configuration.max_aging_slower
end


function find_replaceable_variable_aging (messages)
	local ownmessages=messages:own()

	if ownmessages:len() < configuration.reserved_owns then
		--guarantee for owns satisfied. find replacement between not owns

		local worsts, worst_q=find_worsts(messages)
		--configuration.log('looking for a replacement', #worsts, worst_q)

		--between the worst, find the oldest
		local min_ts, min_ts_mid
		for _, mid in ipairs(worsts) do
			local m = messages[mid]

			if not m.aging_slower and not m.own then
				m.aging_slower = aging_hash(mid)
			end

			local em=(m.ts - m.message._in_transit * m.aging_slower) --estimated emission time

			if not m.own 
			and (not min_ts_mid or min_ts > em) 
			and m.emited > configuration.min_n_broadcasts then
				min_ts_mid, min_ts = mid, em
			end
		end

		return min_ts_mid
	else --ownmessages:len() >= configuration.reserved_owns
		--too much owns. find oldest registered own 
		local min_ts, min_ts_mid
		for mid, m in pairs(ownmessages) do
			if not min_ts_mid or min_ts > m.ts then
				min_ts_mid, min_ts = mid, m.ts
			end
		end

		return min_ts_mid
	end
end

function find_replaceable_window (messages)
	local ownmessages=messages:own()
	local now = socket.gettime()

	if ownmessages:len() < configuration.reserved_owns then
		--guarantee for owns satisfied. find replacement between not owns

		local worsts, worst_q=find_worsts(messages)
		local candidate_random = {}

		--between the worst, find the oldest
		local min_ts, min_ts_mid
		for _, mid in ipairs(worsts) do
			local m = messages[mid]
			local em=m.ts - m.message._in_transit --estimated emission time
			if not m.message.own then
				candidate_random[#candidate_random+1]=mid
			end
			if not m.own and (not min_ts_mid or min_ts > em) then
				min_ts_mid, min_ts = mid, em
			end
		end
		
		--if oldest still too young, select one at random between candidates
		if #candidate_random>0 
		and (not min_ts or min_ts > now-configuration.period_of_random_survival) then
			local i=math.random(1, #candidate_random)
			min_ts_mid = candidate_random[i]
			worst_q = mesage_quality(messages[min_ts_mid])
		end

		return min_ts_mid
	else --ownmessages:len() >= configuration.reserved_owns
		--too much owns. find oldest registered own 
		local min_ts, min_ts_mid
		for mid, m in pairs(ownmessages) do
			if not min_ts_mid or min_ts > m.ts then
				min_ts_mid, min_ts = mid, m.ts
			end
		end

		return min_ts_mid
	end	
end


function find_replaceable_fifo (messages)
	local ownmessages=messages:own()

	if ownmessages:len() < configuration.reserved_owns then
		--guarantee for owns satisfied. find replacement between not owns

		local worsts, worst_q=find_worsts(messages)
		--configuration.log('looking for a replacement', #worsts, worst_q)

		--between the worst, find the oldest
		local min_ts, min_ts_mid
		for _, mid in ipairs(worsts) do
			local m = messages[mid]
			--configuration.log('$$$$', min_ts_mid, min_ts, m.ts, m.message._in_transit )
			local em=m.ts - m.message._in_transit --estimated emission time
			--configuration.log('looking for a replacement ---- ', mid, em)
			--local em=-m.emited
			--local em=m.message.notification_id
			if not m.own 
			and (not min_ts_mid or min_ts > em) 
			and m.emited > configuration.min_n_broadcasts then
				min_ts_mid, min_ts = mid, em
			end
		end

		return min_ts_mid
	else --ownmessages:len() >= configuration.reserved_owns
		--too much owns. find oldest registered own 
		local min_ts, min_ts_mid
		for mid, m in pairs(ownmessages) do
			if not min_ts_mid or min_ts > m.ts then
				min_ts_mid, min_ts = mid, m.ts
			end
		end

		return min_ts_mid
	end
end

