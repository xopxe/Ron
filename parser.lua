module(..., package.seeall);


local sha1, sign_message
if configuration.use_sha1 then
	sha1=require('sha1')
	sign_message=sha1.hmac_sha1_message
else
	print("SHA1 signing disabled")
	sign_message=function(...) return "n/a" end
end


--extracts data (subscirption or notification) from a received line buffer
function extract_data (s) --(lines)
	if not s then return nil, nil, nil, nil, nil end

	--local purge=false

	local ret_views, ret_subscriptions, ret_notifications, ret_subrequest, ret_view_notif={},{},{},{},{}
	local is_filter, message_type
	local target

--configuration.log('+%%%%%%%%%%%%%%%%%%%%%%%')
--configuration.log(s)
--configuration.log('-%%%%%%%%%%%%%%%%%%%%%%%')

	for attrib, op, value in string.gmatch(s, "([%d%w%-_]+)([=<>]?)(%C-)\n") do
--print ('MATCHED:',attrib, op, value)
		if attrib == 'EMITTER' then
			if value==configuration.my_name then return nil,nil,nil,nil end
		elseif attrib == 'VIEWS' then
			--configuration.log("---parsing",attrib)
			target = ret_views --{}
			message_type = attrib
		elseif attrib == 'SUBREQUEST' then
			configuration.log("---parsing",attrib)
			target = ret_subrequest --{}
			message_type = attrib
		elseif attrib == 'NOTIFICATION' then
			--configuration.log("---parsing",attrib)
			target = {}
			message_type = attrib
		elseif attrib == 'SUBSCRIBE' then
			--configuration.log("---parsing",attrib)
			is_filter=false
			target = {}
			message_type = attrib
		elseif attrib == 'FILTER' then
			target.filter={}
			is_filter=true
		elseif attrib == 'END' then
			if message_type == 'VIEWS' then
				ret_views=target --FIXME?
			elseif message_type == 'SUBREQUEST' then
				ret_subrequest=target --FIXME?
			elseif message_type == 'NOTIFICATION' then
				--TODO leer/generar el id?
				target.notification_id = target.notification_id or "notif" .. math.random(2^30) 
				target._in_transit = target._in_transit or 0
				ret_notifications[target.notification_id]=target
			elseif message_type == 'SUBSCRIBE' then
				--TODO leer/generar el id?
				target.subscription_id = target.subscription_id or "sub" .. math.random(2^30) 
				target.p_encounter=tonumber(target.p_encounter)
				is_filter=nil
				--if target._ronsponsable~=configuration.my_name then
					ret_subscriptions[target.subscription_id]=target
				--end
			end
			--target={}
		else
			if attrib and attrib~='' then
				if is_filter then
					--configuration.log("-----sf",attrib,op,value)
					target.filter[#target.filter+1]= {attrib=attrib, op=op, value=value}
				else
					--configuration.log("-----sn ",attrib,value)
					if message_type == 'VIEWS' then 
						if value=='' then
							ret_view_notif[attrib] = true
						else
							local q=tonumber(value) 
							--[[if q<0 then 
								purge=true
								q=-q
							end--]]
    					    		target[attrib]=q
						end
					else
				    		if value then target[attrib]=value end
					end
				end
			end
		end
	end

	--[[
	if purge_mode==false and purge==true then
		for mid,_ in pairs(s_messages) do s_messages:del(mid) end
	end
	purge_mode=purge
	--]]
	
	return ret_views, ret_subscriptions, ret_notifications, ret_subrequest, ret_view_notif
end

function build_subscription_template (s)
	local vlines={[1]='SUBSCRIBE'}

	for k, v in pairs(s) do
		if k~='filter' and k~='p_encounter' then
			vlines[#vlines+1]= tostring(k) .. '=' .. tostring(v)
		end
	end	
	--vlines[#vlines+1]= 'p_encounter=#PENCOUNTER#' --..s.p_encounter
	vlines[#vlines+1]= 'FILTER'
	for _, r in ipairs(s.filter) do
		vlines[#vlines+1]= tostring(r.attrib) .. r.op .. tostring(r.value)
	end
	vlines[#vlines+1]= 'END'

	local ret = table.concat(vlines, '\n')

	return ret
end

---[[
function build_subscriptions (d)
	local firstline='EMITTER='..configuration.my_name
	local vlines, currlen={[1]=firstline}, #firstline
	local ret={}

	for sid, s in pairs(d) do
		--local sout = string.gsub(s.cached_template,'#PENCOUNTER#', s.p_encounter)
		local sout = s.cached_template
		if currlen + #sout < 1500 then
			vlines[#vlines+1], currlen = sout, currlen + #sout
		else
			--new packet
			--FIXME if first fails, fails
			ret[#ret+1]=table.concat(vlines, '\n')
			vlines, currlen={[1]=firstline}, #firstline
		end
	end
	vlines[#vlines+1]=''
	ret[#ret+1]=table.concat(vlines, '\n')

	if configuration.use_sha1 then
		for i, r in ipairs(ret) do
			local signature=sign_message(r)
			ret[i]=r..signature.."\n"
		end
	end

	return ret
end
--]]

local function build_views_notifs (subs, notifs)
	local vlines={}
	for nid, n in pairs(notifs) do
		vlines[#vlines+1] = nid
	end
	if #vlines>0 then
		--vlines[#vlines+1]=''
		return table.concat(vlines, '\n')
	else
		return nil
	end
end

function build_views (subs, notifs)
	local firstline='EMITTER='..configuration.my_name.."\nVIEWS"

	--[[local views_notifs=build_views_notifs (subs, notifs)
	if views_notifs then
		firstline = firstline .. '\n' .. views_notifs
	end--]]

	local vlines, currlen={[1]=firstline}, #firstline + 2 + 4 --plus 2 "\n", plus 1 "END\n"
	local ret={}

	for sid, s in pairs(subs) do
--print ('000', sid)
		local p_encounter = s.p_encounter
		--if purge_mode then p_encounter=-p_encounter end
		local sout = sid .. "=" .. p_encounter
		if currlen + #sout + 1 < 1500 then
			vlines[#vlines+1], currlen = sout, currlen + #sout + 1 --plus "\n"
		else
			--new packet
			--FIXME if first fails, fails
			vlines[#vlines+1]='END\n'
			ret[#ret+1]=table.concat(vlines, '\n')
			vlines, currlen={[1]=firstline}, #firstline + 2 + 4 --plus 2 "\n", plus 1 "END\n"
		end
	end

	for nid, n in pairs(notifs) do
		if currlen + #nid + 1 < 1500 then
			vlines[#vlines+1], currlen = nid, currlen + #nid + 1 --plus "\n"
		else
			break
		end
	end

	vlines[#vlines+1]='END\n'
	ret[#ret+1]=table.concat(vlines, '\n')

	if configuration.use_sha1 then
		for i, r in ipairs(ret) do
			local signature=sign_message(r)
			ret[i]=r..signature.."\n"
		end
	end

--configuration.log ('$$$', ret[1])

	return ret
end

function build_subrequest(sids)
	local firstline='EMITTER='..configuration.my_name.."\nSUBREQUEST"
	local vlines, currlen={[1]=firstline}, #firstline + 2 + 4 --plus 2 "\n", plus 1 "END\n"
	local ret={}

	for sid, _ in pairs(sids) do
		local sout = sid
		if currlen + #sout + 1 < 1500 then
			vlines[#vlines+1], currlen = sout, currlen + #sout + 1 --plus "\n"
		else
			--new packet
			--FIXME if first fails, fails
			vlines[#vlines+1]='END\n'
			ret[#ret+1]=table.concat(vlines, '\n')
			vlines, currlen={[1]=firstline}, #firstline + 2 + 4 --plus 2 "\n", plus 1 "END\n"
		end
	end
	vlines[#vlines+1]='END\n'
	ret[#ret+1]=table.concat(vlines, '\n')

	if configuration.use_sha1 then
		for i, r in ipairs(ret) do
			local signature=sign_message(r)
			ret[i]=r..signature.."\n"
		end
	end

	return ret
end

function build_message_template (d)
	d.notification_id=d.notification_id or "msg" .. math.random(2^30) --TODO generate id

	local vlines={[1]='EMITTER='..configuration.my_name}

	vlines[#vlines+1]= 'NOTIFICATION'
	for k, v in pairs(d) do
		if k~='_in_transit' then
			vlines[#vlines+1]= tostring(k) .. '=' .. tostring(v)
		end
	end
	vlines[#vlines+1]= '_in_transit=#INTRANSIT#'
	vlines[#vlines+1]= 'END\n'

	local ret = table.concat(vlines, '\n')

	return ret
end

function build_message (msg, with_signature)
	local in_transit = (msg.message._in_transit or 0) + (socket.gettime() - msg.ts)
	local m=string.gsub(msg.cached_template,'#INTRANSIT#', string.format('%.4f', in_transit) )

	if configuration.use_sha1 and with_signature then
		local signature=sign_message(m)
		m=m..signature.."\n"
	end

	return m
end

