QueueSet = {}
function QueueSet.new ()
   local inventory = {}
   return {first = 0, last = -1, inventory=inventory}
end

function QueueSet.pushleft (list, value)
   if list.inventory[value] then return end
   local first = list.first - 1
   list.first = first
   list[first] = value
   inventory[value] = true
end

function QueueSet.pushright (list, value)
   if list.inventory[value] then return end
   local last = list.last + 1
   list.last = last
   list[last] = value
   list.inventory[value] = true
end

function QueueSet.popleft (list)
   local first = list.first
   if first > list.last then error("list is empty") end
   local value = list[first]
   list[first] = nil        -- to allow garbage collection
   list.first = first + 1
   list.inventory[value] = nil
   return value
end

function QueueSet.popright (list)
   local last = list.last
   if list.first > last then error("list is empty") end
   local value = list[last]
   list[last] = nil         -- to allow garbage collection
   list.last = last - 1
   list.inventory[value] = nil
   return value
end

function QueueSet.contains(list, value)
   return list.inventory[value]
end

function QueueSet.len(list)
   return list.last-list.first+1
end

