module(..., package.seeall);

local configuration = require("configuration")
local socket = require("socket")

local sha1, sign_message, verify_message
if configuration.use_sha1 then
	sha1=require('sha1')
	sign_message=sha1.hmac_sha1_message
	verify_message=sha1.hmac_sha1_message_verify
else
	print("SHA1 signing disabled")
	sign_message=function(...) return "n/a" end
	verify_message=function(...) return "missing" end
end

local function build_udp_sockets()

	local iface = configuration.service_ip
	local port  = configuration.service_port

	--udp socket for receiving
	local udp_in = assert(socket.udp())
	assert(udp_in:setsockname('*', port)) --(iface, port)) 
	--assert(udp_in:settimeout(configuration.send_views_timeout))
	assert(udp_in:settimeout(0))
	configuration.log("IN Socket", udp_in:getsockname())

	--udp socket for sending out
	--[[local udp_out = assert(socket.udp())
	assert(udp_out:setsockname(iface, 0))
	assert(udp_out:setoption('broadcast', configuration.udp_broadcast))
	assert(udp_out:setoption('dontroute', configuration.udp_dontroute))
	assert(udp_out:setpeername(configuration.broadcast_address, port))
	configuration.log("OUT Socket", udp_out:getsockname())
	configuration.log("OUT Socket To", udp_out:getpeername())
	--]]

	return udp_in --, udp_out
end

--initialization
local udp_in, udp_out = build_udp_sockets()

socket.bind=socket.bind or function (host, port, backlog)
    local sock, err = socket.tcp()
    if not sock then return nil, err end
    sock:setoption("reuseaddr", true)
    local res, err = sock:bind(host, port)
    if not res then return nil, err end
    res, err = sock:listen(backlog)
    if not res then return nil, err end
    return sock
end

--server socket for rnr
--configuration.log("Going to bind RNR Socket", configuration.rnr_iface, configuration.rnr_port)
local rnr_socket = socket.bind(configuration.rnr_iface, configuration.rnr_port) 
--configuration.log("Going to settimeout 0 RNR Socket", tostring(rnr_socket))
rnr_socket:settimeout(0)
configuration.log("RNR Socket", rnr_socket:getsockname())

local clients = {} --keeps list of tcp clients, with associated lines buffer.

local recvt={[1]=rnr_socket, [2]=udp_in} --keeps list of socket to listen on for data.
setmetatable(recvt, {__mode='kv'}) --recvt is weak and will not hold the sockets

--stats info trough http
local stats
local stat_socket
local stat_clients={}
if configuration.http_stats_port >= 0 then
	s_clients=clients
	s_stat_clients=stat_clients
	stats=require('stats')
	stat_socket = socket.bind('*', configuration.http_stats_port) 
	recvt[#recvt+1] = stat_socket
end

local last_udp_sent --for filtering out our own emissions

function ron_send (m)
	if udp_out and udp_out:send(m) then
		last_udp_sent = m
		return
	end
	udp_out = assert(socket.udp())
	if not (udp_out:setsockname(configuration.service_ip, 0)) then return end
	if not (udp_out:setoption('broadcast', configuration.udp_broadcast)) then return end
	if not (udp_out:setoption('dontroute', configuration.udp_dontroute)) then return end
	if not (udp_out:setpeername(configuration.broadcast_address, configuration.service_port)) then return end
	if udp_out:send(m) then
		last_udp_sent = m
		return
	end
end

--reads data from udp or tcp socket, whatever comes first. 
--if reads from udp, returns 'ron',nil, data, err
--if reads from tcp, returns 'rnr',skt, data, err
local tcp_is_notif=false
function receive()
	local recvt_ready, _, err=socket.select(recvt, nil, 
	                           configuration.tick + 0.1*configuration.tick*math.random())
--configuration.log('.', err)
	if err then
		return 'ron', nil, nil, err
	end

--configuration.log(':', recvt_ready[udp_in],recvt_ready[rnr_socket],recvt_ready[stat_socket],recvt_ready and recvt_ready[1])
--configuration.log('::', clients[recvt_ready and recvt_ready[1]], stat_clients[recvt_ready and recvt_ready[1]])

	--ready to read udp packet
	if recvt_ready[udp_in] then
		local m, err=udp_in:receive()
		if m==last_udp_sent then m=nil end
		if m and configuration.use_sha1 then
--		print ("~~~~~\n", m,"~~~~~")
			local m, signature=string.match(m, '^(.-END\n)(%C*)\n?$')
--			print ("!!!!!", #(m or ''), signature, sign_message(m), verify_message(m, signature))
			if verify_message(m, signature) ~= 'ok' then
				print("WARN: Purging message (signature check failure)")
				return 'ron', nil, nil, err
			end
		end

		return 'ron', nil, m, err
	end
	
	--ready to accept new tcp connection
	if recvt_ready[rnr_socket] then
		local client, err=rnr_socket:accept()
		if client then
			clients[client]={}
			table.insert(recvt,client)			
		end
		return 'rnr', client, nil, err
	end

	--ready to accept stats client
	if recvt_ready[stat_socket] then
--configuration.log('%%%%%%%%%%%', 'connecting')
		local client, err=stat_socket:accept()
		client:settimeout(10)
		if client then
			--client:send("HTTP/1.1 200/OK\r\nContent-Type:text/html\r\n\r\n")
			stat_clients[client] = true
			table.insert(recvt,client)
--configuration.log('%%%%%%%%%%%', 'connecting!!!!!!!!!!!!!',client)
		end
		return 'ron', nil, nil, err
	end


	--ready to read tcp (rnr) data
	local client=recvt_ready[1]
	if clients[client] then
		local s,err = client:receive('*l')
		if err=='closed' then
			clients[client]=nil
			for k, v in ipairs(recvt) do 
				if client==v then 
					table.remove(recvt,k) 
					break
				end
			end
			reset_own(client)
		end
		
		local ret
		if s and s~='' then
		    if s=='NOTIFICATION' then tcp_is_notif=true end
			table.insert(clients[client], s)
			if s == 'END' then
			    if tcp_is_notif then
    				table.insert(clients[client], '_ronsponsable='..tostring(configuration.my_name))			        
			        tcp_is_notif=false
			    end
				table.insert(clients[client], '')
				ret=table.concat(clients[client], "\n") --clients[client]
				clients[client]={}
			end
		end

		return 'rnr', client, ret, err
	end

	--the tcp data is a stat client	
	if stat_clients[client] then
--configuration.log('====stat')
		local s,err = client:receive('*l')
		local close_connection
configuration.log('====stat received', s,err)
		if err=='closed' then
			close_connection=true
		else
--			local f=string.match(s, 'GET (%S+) HTTP/1.1')
			local f,p=string.match(s, '^GET ([%/%.%d%w%-_]+)[%?]?(.-) HTTP/1.1$')
--configuration.log('====incomming', f,p)
			if f then
				--close_connection=true
				s=stats.get_page[f](p)
--configuration.log('====stat sending', #s)
				client:send(s..'\n')
			else
				client:send("HTTP/1.1 200/OK\r\nContent-Type:text/html\r\n\r\nError parsing GET\n")
			end
--configuration.log('====end')
		end

		if close_connection then 
			client:close()
			stat_clients[client]=nil
			for k, v in ipairs(recvt) do 
				if client==v then 
					table.remove(recvt,k) 
					break
				end
			end
		end
		return 'ron', nil, nil, err
	end

end

