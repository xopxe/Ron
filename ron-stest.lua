#!/usr/bin/lua

local socket = require("socket")


--aux
--ejecuta un s en la consola y devuelve la salida
local run_shell = function(s)
	local f = io.popen(s) -- runs command
	local l = f:read("*a") -- read output of command
	f:close()
	return l
end
local function get_if_ip(iface)
	local ifconfig = run_shell("ifconfig	" .. tostring(iface))
	local ip=string.match(ifconfig, "inet addr:(%S+)") 
	local bcast=string.match(ifconfig, "Bcast:(%S+)") 
	return ip, bcast
end
--/aux

local logfile = assert(io.open("ron_stest.log","w"))
logfile:write(os.time(), "\tStarted logging\n") 
local function log (...) 
	print(...)
	logfile:write(os.time()) 
	for i=1, select("#", ...) do			
		local arg=select(i, ...)
		logfile:write("\t", tostring(arg)) 
	end
	logfile:write("\n")
	logfile:flush()
end



local my_id=arg[1]

local tcp=assert(socket.connect("127.0.0.1", 8182))
tcp:settimeout(nil)

local s="SUBSCRIBE\nn=node_"..my_id.."\nFILTER\na=1\nb>0.5\nEND\n"
log(s)
assert(tcp:send(s))
socket.sleep(0.5)

---[[
while 1 do
	local m, err = tcp:receive()
	if err=='closed' then return end
	log(m)
end
--]]

