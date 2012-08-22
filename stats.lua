module(..., package.seeall);

local dottify = require("dotlua")

local configuration = require("configuration")
local socket = require("socket")
local networking = require("networking")


local template
local function load_template ()
	local served, err = io.open('stats/template.txt', "r")
	if served ~= nil then
		template = served:read("*all")
	else
		--print("Error opening template:", err)
	end
end


local function default_page()
	return "HTTP/1.0 404 Not Found\r\nContent-Type:text/html\r\n\r\n"
		.."<h3>404 Not Found!</h3><hr/><small>RON stats</small>"
end

get_page={}
setmetatable(get_page, {__index=function() return default_page end})


local function build_message_rows()
	local currtime=socket.gettime()
	local s={[1]='<tr><td>id</td><td>received</td><td>last_seen</td><td>in_transit</td><td>watcher id</td><td>value</td></tr>'}
	for k, v in pairs(s_messages) do
		local m=v.message
		local id
		if m.reply_to then 
			id=k .. "<br><small>reply to "..m.reply_to.."</small>"
		else
			id=k
		end
		s[#s+1]=string.format('<tr><td>%s</td><td>%.2f</td><td>%.2f</td><td>%.2f</td><td>%s</td><td>%s</td></tr>', 
			id, currtime-v.ts, currtime-v.last_seen,  v.message._in_transit
			,m.watcher_id or '',m.value or '')
	end
	return table.concat(s, '\n')
end

local function build_filter(sub)
	local s= {} --{[1]=''}
	for _, v in ipairs(sub.filter) do
		s[#s+1]=v.attrib..v.op..v.value..'; '
	end
	return table.concat(s, '\n')
end

local function build_subscriptions_rows()
	local ns=0
	local currtime=socket.gettime()
	local s={[1]='<tr><td>id</td><td>received (secs ago)</td><td>last seen (secs ago)</td></td><td>p_encounter</td></td><td>filter</td></tr>'}
	for k, v in pairs(s_subscriptions) do
		s[#s+1]=string.format('<tr><td>%s</td><td>%.2f</td><td>%.2f</td></td><td>%.2f</td></td><td>%s</td></tr>',
			k, currtime-v.ts, currtime-v.last_seen, v.p_encounter, build_filter(v) )
		ns=ns+1
		--s[#s+1]='<tr><td>'
		--s[#s+1]=k
		--s[#s+1]='</td><td>'
		--s[#s+1]=v.ts..'</td><td>'..v.last_seen..'</td><td>'..v.p_encounter..'</td><td>'..build_filter(v)
		--s[#s+1]='</td></tr>'
	end
	return table.concat(s, '\n'), ns
end

get_page["/index.htm"] = function ()
	local ci, sci=0, 0
	for _ in pairs(networking.s_clients) do ci=ci+1 end
	for _ in pairs(networking.s_stat_clients) do sci=sci+1 end
	local subs, nsubs=build_subscriptions_rows()

	local rep = {
		['<!--NODENAME-->']=configuration.my_name,
		['<!--STATCLI-->']=sci,
		['<!--TIME-->']=socket.gettime(),
		['<!--MESSAGES-->']=build_message_rows(),
		['<!--SUBSCRIPTIONS-->']=subs,
		['<!--NSUBSCRIPTIONS-->']=nsubs,
		['<!--NNOTIFS-->']=s_messages:len(),
		['<!--MAXNOTIFS-->']=configuration.inventory_size,
		['<!--TICK-->']=configuration.tick,
		['<!--SENDTIMEOUT-->']=configuration.send_views_timeout,
		['<!--DELAYEMIT-->']=configuration.delay_message_emit,
		['<!--AUTOREFRESH-->']=''
	}
--load_template()
	return "HTTP/1.1 200/OK\r\nContent-Type:text/html\r\n\r\n" 
		.. string.gsub(template, '(<!%-%-%w+%-%->)', rep)
end

get_page["/indexauto.htm"] = function ()
	local ci, sci=0, 0
	for _ in pairs(networking.s_clients) do ci=ci+1 end
	for _ in pairs(networking.s_stat_clients) do sci=sci+1 end
	local subs, nsubs=build_subscriptions_rows()

	local rep = {
		['<!--NODENAME-->']=configuration.my_name,
		['<!--RNRCLI-->']=ci,
		['<!--STATCLI-->']=sci,
		['<!--TIME-->']=socket.gettime(),
		['<!--MESSAGES-->']=build_message_rows(),
		['<!--SUBSCRIPTIONS-->']=subs,
		['<!--NSUBSCRIPTIONS-->']=nsubs,
		['<!--NNOTIFS-->']=s_messages:len(),
		['<!--MAXNOTIFS-->']=configuration.inventory_size,
		['<!--TICK-->']=configuration.tick,
		['<!--SENDTIMEOUT-->']=configuration.send_views_timeout,
		['<!--DELAYEMIT-->']=configuration.delay_message_emit,
		['<!--AUTOREFRESH-->']='<META HTTP-EQUIV="refresh" CONTENT="5; url=/indexauto.htm">'
	}
--load_template()
	return "HTTP/1.1 200/OK\r\nContent-Type:text/html\r\n\r\n" 
		.. string.gsub(template, '(<!%-%-%w+%-%->)', rep)
end

get_page["/"]=get_page["/index.htm"]

get_page["/favicon.ico"] = function ()
	local served, err = io.open('stats/favicon.ico', "rb")
	if served ~= nil then
		local content = served:read("*all")
		return "HTTP/1.1 200/OK\r\nContent-Type:image/x-icon\r\n\r\n" .. content
	else
		--print("Error opening favicon:", err)
		return default_page()
	end
end

get_page["/snapshotsubs.dot"] = function ()
	dottify("/tmp/subs.dot", s_subscriptions, 'nometatables')
	local served, err = io.open("/tmp/subs.dot", "r")
	if served ~= nil then
		local content = served:read("*all")
		os.remove("/tmp/subs.dot")
		return "HTTP/1.1 200/OK\r\nContent-Type:application/x-graphviz\r\n\r\n" .. content
	end
	return get_page["/"]()
end

get_page["/snapshotnotifs.dot"] = function ()
	dottify("/tmp/messages.dot", s_messages, 'nometatables')
	local served, err = io.open("/tmp/messages.dot", "r")
	if served ~= nil then
		local content = served:read("*all")
		os.remove("/tmp/messages.dot")
		return "HTTP/1.1 200/OK\r\nContent-Type:application/x-graphviz\r\n\r\n" .. content
	end
	return get_page["/"]()
end

get_page["/run"] = function (p)
	code=string.match(p, '^code=(.*)$')
	--print ('extracted code',p,code )

	local runproc, err = loadstring (code)
	if not runproc then
		--print ("Error loading",err)
		return "HTTP/1.1 200/OK\r\nContent-Type:text/html\r\n\r\nError loading code:"..err	
	end
	
	--setfenv (runproc, configuration)       
	local ret 
	local status, err = pcall(function() ret=runproc() end)
	if not status then ret="Error: "..tostring(err) end
	return "HTTP/1.1 200/OK\r\nContent-Type:text/html\r\n\r\n"..tostring(ret) 
	--return get_page["/"]()
end

load_template()
