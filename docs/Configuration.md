# Configuration

The configuration file s a lua script that sets values to attributes. The available attributes are (the default values are shown in parentheses):

## Service parameters

**enabled** (true) enables the ron protocol.

**my\_name** ("node"..math.random()) Unique name for the node

**save\_each** (-1) Number of secs between automatic saves to disk (negative to disable)


## Network parameters

**rnr\_iface** ('127.0.0.1') Interface on which accept clients

**rnr\_port** (8182)  Port on which accept clients Defaults to

**service\_ip** ("*") Interface to use for ron protocol

**service\_port** (8888) Port to use for ron protocol

**udp\_broadcast** (true) Whether to set the _broadcast_ flag on the socket used for opportunistic messaging 

**udp\_dontroute** (true) Whether to set the _dontroute_ flag on the socket used for opportunistic messaging

**broadcast\_address** ("255.255.255.255") Adress used when broadcasting the ron protocol


## Protocol parameters

**inventory\_size** (10)	Max number of messages carried

**reserved\_owns** (5) Guaranteed number of slots for own messages in inventory

**max\_owning\_time** (60\*60\*24s)	Max time own messages are kept

**max\_notif\_transmits** (math.huge) Max number of transmissions for each notification

**max\_ownnotif\_transmits** (math.huge) Max number of transmissions for each own notification

**max\_notifid\_tracked** (5000)	Number of notification ids kept for notif. reincidence control

**tick** (2) Time step

**send\_views\_timeout** (60s) Timeout for sending views.

**delay\_message\_emit** (5s) Minimum time between appearances of a message in the collision domain

**P\_encounter** (0.1) Subscription reinforcing

**gamma** (0.99) Subscription aging

**min\_p\_encounter** (0.0001) If p\_enconter falls bellows this, the subscription is removed.


## Buffer management options

**ranking\_find\_replaceable** (ranking.find\_replaceable\_fifo) Buffer management policy to use. The policies and their parameters are:

### find\_replaceable\_fifo

**min\_n\_broadcasts** (0)

### find\_replaceable\_window

**period\_of\_random\_survival** (24\*60\*60s)

### find\_replaceable\_diversity\_array

**max\_size\_diversity\_array** ( (inventory\_size - reserved\_owns) / 20)

**diversity\_survival\_quotient** (0.02)

### find\_replaceable\_seen\_rate

**min\_time\_for\_averaging** (60\*60s)

### for find\_replaceable\_variable\_aging

**max\_aging\_slower** (1/24)

### find\_replaceable\_homogeneous 

**number\_of\_ranges** (10)

**ranking\_window** (24\*60\*60s)



## Tooling parameters

**log** (function(...) print(os.time(), ...) end) A logging function

**http\_stats\_port** (8188) Stats info port, -1 disables

**use\_sha1** (true) Use sha1 module for signing messages

**use\_sha1\_cache** (true) Faster sha1, uses more memory	

**sha1\_key** ("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx") Key used to sign messages


