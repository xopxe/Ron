#!/usr/bin/lua

--package.path=package.path..";/usr/local/nctuns/tools/?.lua"

local configuration = require("configuration")
if arg[1] then configuration.load(arg[1]) end
local networking = require("networking")
local parser = require("parser")
local m_s_tables=require("m_s_tables")
--local ranking = require("ranking")
local wmonitor = require("wmonitor")
local savefile = io.open('data.save', 'r')
if configuration.save_each>0 or savefile then dofile('table.save-0.94.lua') end

--[[
--messages carried around
local messages = tracked_table.make_MessageTable () -- {[id]={ message, last_seen, delivered={}, emited, emits, seen, ts, [own]}}

--network view
local subscriptions = {}
--subscriptions[sid] = {subscription_id, filter, p_encounter=1, last_success, last_seen=socket.gettime(), ts, [own]}
--]]

local messages = m_s_tables.messages
local subscriptions = m_s_tables.subscriptions
local savedata = {['messages']=m_s_tables.messages, ['subscriptions']=m_s_tables.subscriptions}

--stats plugin support
--if configuration.http_stats_port >= 0 then
	s_messages=messages
	s_subscriptions=subscriptions
--end

local meta_weak_value = {__mode='v'}
--pending messages to be emitted
local pending_messages = {}
setmetatable(pending_messages,meta_weak_value)

local pending_subrequest = {}
setmetatable(pending_subrequest,meta_weak_value)

local pending_subs = {}
setmetatable(pending_subs,meta_weak_value)

local ranking_find_replaceable = configuration.ranking_find_replaceable


--to be called when a local client dies. frees it's socket from all delivered messages
function reset_own (skt)
	configuration.log('resetting messages for dead client')
	for mid, m in pairs(messages:own()) do
		m.delivered[skt]=nil
		--guard messages after emmiter client died?
		--if m.own==skt then messages:del(mid) end
	end
	for sid, s in pairs(subscriptions) do
		if s.own==skt then
			subscriptions:del(sid)
		end
	end
end

--deliver notifs to rnr, and marks them as delivered
local function deliver_to_rnr (message, skt)
	--local skt=subscription.own
	skt:send( parser.build_message(message, false) )
	message.delivered[skt]=true
end

--sends the views list to the net
local function emit_views ()
	local msgs = parser.build_views(subscriptions, messages)
	for id, m in ipairs(msgs) do
		configuration.log ("sending views", id, string.len(m), "bytes")
		networking.ron_send(m)
	end
end

--creates a subscription and stores it
local function new_sub (sid, s, skt)
	configuration.log("---------new subscription registered", sid, #s.filter, "rows")
	local t=socket.gettime()
	local p_encounter
	if skt then 
		p_encounter=1 
	else
		p_encounter=0.5 --5*configuration.min_p_encounter  --1 TODO pensarlo, con que calidad aparece? (no tenemos acceso al q de donde viene?)
	end
	subscriptions:add(sid,{subscription_id=sid, filter=s.filter, p_encounter=p_encounter, 
		last_seen=t, ts=t, cached_template=parser.build_subscription_template(s),own=skt})
end

--updates the p_encounters to the subscriptions mentioned in in_subscriptions. 
--queries request for new subscriptions
local function update_views (in_views, skt)

	--aging
	local now = socket.gettime()
	for sid, s in pairs(subscriptions) do
		if (not s.own) and ((not in_views[sid]) or (in_views[sid] < s.p_encounter)) then
			s.p_encounter=s.p_encounter * configuration.gamma^(now-s.last_seen)
			s.last_seen=now
		end
		--delete if p_encounter too small
		if s.p_encounter < (configuration.min_p_encounter or 0) then
			configuration.log('purging subscription', sid, ' with p_encounter',s.p_encounter)
			subscriptions:del(sid)
		end
	end
	
	--reinforcing
	for isid, p in pairs(in_views) do
		local s=subscriptions[isid]
--print ('%%%%%%%%%%%', isid, p, s)
		if not s then
			--new_sub(isid, is, skt)
			pending_subrequest[isid]=true
		else
			if s.p_encounter<p and not s.own then
				local p_old=s.p_encounter
				s.p_encounter = p_old + ( 1 - p_old ) * p * configuration.P_encounter
			end
		end
	end
end


--selects messages to be sent out in response to views received
--parameters should be set of subscription ids.
local function select_for_subs (vs, skipnotif)
	local now=socket.gettime()
	for mid, m in pairs(messages) do
		local matches=m.matches
		for sid, _ in pairs(vs) do  --sid,p_encounter
			local s=subscriptions[sid]
			if s and matches[s] then
				s.last_success=now
				local own=s.own
				if not own then
					if now - m.last_seen > configuration.delay_message_emit then
					    --configuration.log('%%%%', mid, skipnotif, skipnotif and skipnotif[mid])
						if not skipnotif[mid] then
							pending_messages[mid]=m
						end
					end
				elseif not m.delivered[own] then
					deliver_to_rnr(m,own) --out_own[mid]=sid
				end
			end
		end
	end
end


--selects messages from a received list to be forwarded to rnr clients.
local function select_from_notifs (ms)
	local out, out_own={}, {}
	for seq, _ in pairs(ms) do
		local m=messages[seq]
		if m then
			local matches=m.matches
			for sid, s in pairs(subscriptions) do
				if matches[s] then
					s.last_success=socket.gettime()
					local own=s.own
					if own and not m.delivered[own] then
						deliver_to_rnr(m,own)
					end
				end
			end
		end
	end

	return out, out_own
end

--queues subscriptions for transmission
local function queue_subs_for_request(subrequests)
	for sid, _ in pairs(subrequests) do
        --configuration.log('=SRQ', sid)
		pending_subs[sid]=subscriptions[sid]
	end
end

--sends each of the messages to the net.
local function emit_pending_messages ()
	if not next(pending_messages, nil) then return end
	--local mret=parser.build_messages(pending_messages)
	for _, msg in pairs(pending_messages) do
		local m = parser.build_message(msg, true)
		msg.emited=msg.emited+1
		--configuration.log ("sending notification", string.len(m), "bytes")
		networking.ron_send(m)
	end
	pending_messages={}
end

--sends each of the messages to the net.
local function emit_pending_subs ()
	if not next(pending_subs, nil) then return end
	local msub=parser.build_subscriptions(pending_subs) --msg.cached_string
	for _, m in ipairs(msub) do
		configuration.log ("sending subscription", string.len(m), "bytes")
		networking.ron_send(m)
	end
	pending_subs={}
end

--sends each of the messages to the net.
local function emit_pending_subrequest ()
	if not next(pending_subrequest, nil) then return end
	local mrqs=parser.build_subrequest(pending_subrequest)
	for _, m in ipairs(mrqs) do
		configuration.log ("sending subscription request", string.len(m), "bytes")
		networking.ron_send(m)
	end
	pending_subrequest = {}
end

local function process_full_subs (subs, skt)
	for sid, s in pairs(subs) do
		if not subscriptions[sid] then
			new_sub (sid, s, skt)
			--trigger notifications as if views was received			
			select_for_subs ({[sid]=subscriptions[sid].p_encounter}, {})
		end
		pending_subs[sid]=nil
		pending_subrequest[sid]=nil
	end
end

require "queue_set"
local seen_notifs = QueueSet.new()
--make_LimitedTable (configuration.max_notifid_tracked)

local meta_weak_key = {__mode='k'} --weak keys metatable
--creates an message and stores it
local function new_msg (nid, n, skt)

	if QueueSet.contains(seen_notifs, nid) then return end
	if QueueSet.len(seen_notifs)>=configuration.max_notifid_tracked then
		QueueSet.popleft(seen_notifs)
	end
	QueueSet.pushright(seen_notifs, nid)

	configuration.log("---------new message registered", n.notification_id, skt~=nil)
	local mt=parser.build_message_template(n)
	local delivered={}, {}
	setmetatable(delivered,meta_weak_key)
	local msg={message=n, last_seen=socket.gettime(), cached_template=mt, delivered=delivered, 
			own=skt, emited=0, seen=1, ts=socket.gettime()}
	messages:add(nid, msg)
	
	--[[
	--own message, emit it.
	if skt then 
		networking.ron_send(parser.build_message(msg)) 
		messages[nid].last_seen=socket.gettime()
	end
	--]]
end

--adds a message into a messages list (making space if needed)
local function merge(msgs, skt)
--configuration.log('messages',messages:len(), messages:own():len())

	--messages maintenance
	local t=socket.gettime()
	for mid, m in pairs(messages) do
		if m.own then
			if t - m.ts > configuration.max_owning_time then
				configuration.log("==========Purging old own mesage", mid, m.ts)
				messages:del(mid)
			end
			if m.emited >= configuration.max_ownnotif_transmits then
				configuration.log("==========Purging own mesage on transmit count", mid)
				messages:del(mid)
			end
		else
			if m.emited >= configuration.max_notif_transmits then
				configuration.log("==========Purging mesage on transmit count", mid)
				messages:del(mid)
			end
		end
	end


--[[
	--update last_seen on received messages
	for mid, _ in pairs(msgs) do
		local m=messages[mid]
		if m then
			m.last_seen=socket.gettime()
			pending_messages[mid] = nil --we were to emit this, don't.
		end
	end
--]]
	
	for nid, n in pairs(msgs) do
		local m=messages[nid]
		if m then
			m.last_seen=socket.gettime()
			m.seen=m.seen+1
			pending_messages[nid] = nil --if we were to emit this, don't.
		else	
			new_msg (nid, n, skt)
			--make sure table doesn't grow beyond inventory_size
			while messages:len()>configuration.inventory_size do
				local mid=ranking_find_replaceable(messages)
				messages:del(mid or nid)
				configuration.log("messages shrinking", mid or nid, 'to', messages:len())
			end
		end
	end
end

local function logp()
    --[[
    local p=0
    local _, s = next(subscriptions, nil)
    if s then p=(s.p_encounter or 0) end
    configuration.logp(p)
    --]]

    --[[
    local now=socket.gettime()
    local tmax=0
    for _,m in pairs(messages) do
        local t=m.message._in_transit+(now-m.ts)
        if t>tmax then tmax=t end
    end
    configuration.logp(tmax)
    --]]

    --[[
    local now=socket.gettime()
    local t=0
    for _,m in pairs(messages) do
        t=t + m.message._in_transit+(now-m.ts)
    end
    if messages:len()>0 then
        configuration.logp(t / messages:len())
    else
        configuration.logp(0)
    end 
    --]]

end

if savefile then
	savefile:close()
	savedata=table.load('data.save')
	m_s_tables.messages=savedata['messages']
	m_s_tables.subscriptions=savedata['subscriptions']
	m_s_tables.init()
	messages = m_s_tables.messages
	subscriptions = m_s_tables.subscriptions
	--stats plugin support
	if configuration.http_stats_port >= 0 then
		s_messages=messages
		s_subscriptions=subscriptions
	end
end

--emit_views()
--local last_emit=socket.gettime()
local last_wmonitor, last_emit, last_pending, last_save = 0, 0, 0, 0
local trigger_wmonitor

configuration.log("===Listening===")
while 1 do
	local message_type,skt, m, err = networking.receive()
	local now=socket.gettime()

	if configuration.enabled then
		if m then
			--logp()
			local views, subs, notifs, subrequests, view_notif = parser.extract_data(m)

			--discard own notifs that traveled back to us
			if message_type=='ron' and notifs then
				for k,v in pairs(notifs) do
					if v._ronsponsable==configuration.my_name then
					    configuration.log('purged by ronsponsable', k, v._ronsponsable)
					    notifs[k]=nil
					end
				end
			end

			if subs then
			    process_full_subs(subs,skt)
			end

			if views then
			    update_views(views, skt)
			    select_for_subs(views, view_notif) --all notifs against incomming subs.
			end

			if notifs then
				for nid, n in pairs(notifs) do
					if n._purge=='true' then
						for mid, _ in pairs(messages) do 
							print ('PURGING!', mid)
							messages:del(mid) 
						end
						notifs={}
						break
					end
				end
				merge(notifs, skt)
				select_from_notifs(notifs) --incoming notifs against all subs.
			end

			if subrequests then
			    queue_subs_for_request(subrequests)
			end
		end

		--decide if check for new assocs.
		if configuration.check_associated_timeout >0 then
			--print('%%%%%%%%%%%%', socket.gettime(), last_wmonitor, 
			--	socket.gettime()-last_wmonitor,configuration.check_associated_timeout)
			if socket.gettime()-last_wmonitor > configuration.check_associated_timeout then
				trigger_wmonitor=wmonitor.new_associated()
				last_wmonitor=socket.gettime()
			else
				trigger_wmonitor=false
			end
			--print('%%%%%%%%%%%%', trigger_wmonitor)
		end

		if now-last_pending > configuration.tick then
			emit_pending_messages()
			emit_pending_subrequest()
			emit_pending_subs()
			last_pending=now
		end

		if now-last_save > configuration.save_each and configuration.save_each>0 then
			local _, err=table.save(savedata, 'data.save')
			if err then
				configuration.log('Error dumping data:', err)
			end
			last_save=now
		end

		if now-last_emit > configuration.send_views_timeout or m=='trigger' then
			--logp()
			emit_views()
			last_emit=now
		end
	else
	    --configuration.log("===Disabled===")
    end --if enabled
end


