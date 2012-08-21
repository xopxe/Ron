module(..., package.seeall);

require "ranking"

local function randomize ()
	local fl = io.open("/dev/urandom");
	local res = 0;
        local mult={256,256,256,128} --bug de Lua! randomseed lee 31 bits
        for f = 1, 4 do res = res*mult[f]+(fl:read(1)):byte(1, 1); end;                                                                     
	fl:close();
	math.randomseed(res);
end;

randomize()

--default values
rnr_iface = '127.0.0.1'
rnr_port = 8182
my_name = "node"..math.random()	--name for this node
service_ip	= "*"		--ip where i listen
service_port 	= 8888
udp_broadcast 	= true
udp_dontroute 	= true
broadcast_address  = "255.255.255.255" --adress used when broadcasting
enabled         = true
inventory_size	= 10		--max number of messages carried
reserved_owns	= 5		--guaranteed number of slots for own messages in inventory
max_owning_time = 60*60*24	--max time own messages are kept
max_notif_transmits = math.huge --max number of transmissions for each notification
max_ownnotif_transmits = math.huge --max number of transmissions for each own notification
max_notifid_tracked = 5000	--number of notification ids kept for notif. reincidence control

save_each 	= -1		--number of secs between automatic saves (negative to disable)

tick = 2			--time step
check_associated_timeout = 0 	--timeout for checking assocs (0 disables)
send_views_timeout = 60		--timeout for sending views.
delay_message_emit = 5		--minimum time between appearances of a message in the net

http_stats_port	= 8188		--stats info port, -1 disables

use_sha1 	= true		--load sha1 module
use_sha1_cache	= true  	--faster sha1, uses more memory	
sha1_key	= "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" --key used to sign messages

ranking_find_replaceable = ranking.find_replaceable_fifo

--for find_replaceable_fifo
min_n_broadcasts = 0 --see ranking.lua

--for find_replaceable_window
period_of_random_survival = 60*60*24

-- for find_replaceable_diversity_array
max_size_diversity_array = ( (inventory_size - reserved_owns) / 20 )
diversity_survival_quotient = 0.02

--for find_replaceable_seen_rate
min_time_for_averaging = 60*60

--for find_replaceable_variable_aging
max_aging_slower = 1/24

--for find_replaceable_homogeneous 
number_of_ranges = 10	
ranking_window = 60*60*24

--based on PROPHET, http://www.dtnrg.org/docs/specs/draft-lindgren-dtnrg-prophet-02.txt
P_encounter 	= 0.1 --TODO
beta		= 0.5 --TODO
gamma		= 0.99--TODO

min_p_encounter = 0.0001	--if p_enconter falls bellows this, the subscription is removed.

--a logging function
log 	= function(...) print(os.time(), ...) end

--loads from a configuration file
function load(file)
	local f, err = loadfile(file)
	assert(f,err)
	setfenv(f, configuration)
	f()
end

