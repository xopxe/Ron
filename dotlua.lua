-- generate a graphviz graph from a lua table structure

module(..., package.seeall);


local function append( tab, ... )
  for i = 1, select( '#', ... ) do
    tab[ #tab + 1 ] = (select( i, ... ))
  end
  return tab
end

local html_rep = {
	['<']='&lt;',
	['>']='&gt;',
}

local function abbrev( str, data )
  local escape = "\\\\"
  if data.use_html then
    escape = "\\"
  end
--  local s = string.gsub( str, "[^%w?!=/+*-_.:,; ]", function( c )
--  --local s = string.gsub( str, "[^%w_]", function( c )
--    return escape .. string.byte( c )
--  end )
  local s=string.gsub(str, '(%W)', html_rep)
  if string.len( s ) > 20 then
    s = string.sub( s, 1, 17 ) .. "..."
  end
  return "'" .. s .. "'"
end

local function update_node_depth( val, data, depth )
  data.node2depth[ val ] = math.min( data.node2depth[ val ] or depth, depth )
end

local function define_node( data, node )
  assert( not data.node2id[ node.value ] )
  local id = data.n_nodes
  data.n_nodes = data.n_nodes + 1
  data.node2id[ node.value ] = id
  append( data.nodes, node )
  return id
end

local function define_edge( data, edge )
  append( data.edges, edge )
end

local function get_metatable( val, enabled )
  if enabled then
    if type( debug ) == "table" and
       type( debug.getmetatable ) == "function" then
      return debug.getmetatable( val )
    elseif type( getmetatable ) == "function" then
      return getmetatable( val )
    end
  end
end

local function get_environment( val, enabled )
  if enabled then
    if type( debug ) == "table" and
       type( debug.getfenv ) == "function" then
       return debug.getfenv( val )
    elseif type( getfenv ) == "function" and
           type( val ) == "function" then
      return getfenv( val )
    end
  end
end



-- generate dot code for references
local function dottify_metatable_ref( val, id1, mt, id2, data )
  append( data.edges, {
    A = val, A_id = id1,
    B = mt, B_id = id2,
    style = "dashed",
    arrowtail = "odiamond",
    label = "metatable",
    color = "blue"
  } )
  data.nodes[ data.node2id[ val ] ].important = true
  data.nodes[ data.node2id[ mt ] ].important = true
end
local function dottify_environment_ref( val, id1, env, id2, data )
  append( data.edges, {
    A = val, A_id = id1,
    B = env, B_id = id2,
    style = "dotted",
    arrowtail = "dot",
    label = "environment",
    color = "red"
  } )
  data.nodes[ data.node2id[ val ] ].important = true
  data.nodes[ data.node2id[ env ] ].important = true
end
local function dottify_upvalue_ref( val, id1, upv, id2, data, name )
  append( data.edges, {
    A = val, A_id = id1,
    B = upv, B_id = id2,
    style = "dashed",
    label = name or "#upvalue",
    color = "green"
  } )
  data.nodes[ data.node2id[ val ] ].important = true
  data.nodes[ data.node2id[ upv ] ].important = true
end
local function dottify_ref( val1, id1, val2, id2, data )
  append( data.edges, {
    A = val1, A_id = id1,
    B = val2, B_id = id2,
    style = "solid",
    arrowhead = "normal",
  } )
end


-- forward declarations
local dottify_table, dottify_userdata, dottify_thread, dottify_function


local function make_label( tab, v, data, id, subid, depth )
  if type( v ) == "table" then
    local id2 = dottify_table( v, data, depth+1 )
    dottify_ref( tab, id..":"..subid, v, id2..":0", data )
    return tostring( v )
  elseif type( v ) == "userdata" then
    local id2 = dottify_userdata( v, data, depth+1 )
    dottify_ref( tab, id..":"..subid, v, id2, data )
    return tostring( v )
  elseif type( v ) == "function" then
    local id2 = dottify_function( v, data, depth+1 )
    dottify_ref( tab, id..":"..subid, v, id2, data )
    return tostring( v )
  elseif type( v ) == "thread" then
    local id2 = dottify_thread( v, data, depth+1 )
    dottify_ref( tab, id..":"..subid, v, id2, data )
    return tostring( v )
  elseif type( v ) == "string" then
    return abbrev( v, data )
  elseif type( v ) == "number" or type( v ) == "boolean" then
    return tostring( v )
  else
    error( "unsupported primitive lua type" )
  end
end


function dottify_table( tab, data, depth )
  assert( type( tab ) == "table" )
  update_node_depth( tab, data, depth )
  if not data.node2id[ tab ] then
    local node = {
      value = tab
    }
    local id = define_node( data, node )
    local label
    -- build label for this table
    if data.use_html then
      node.shape = "plaintext"
      label = [[<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0">
  <TR><TD PORT="0" COLSPAN="2" BGCOLOR="lightgrey">]] .. tostring( tab ) .. [[
</TD></TR>
]]
    else
      node.shape = "record"
      label = "{ <0> " .. tostring( tab )
    end
    local handled = {}
    local n = 1
    -- first the array part
    for i,v in ipairs( tab ) do
      local el_label = make_label( tab, v, data, id, n, depth )
      if data.use_html then
        label = label .. [[
  <TR><TD PORT="]] .. n .. [[" COLSPAN="2">]] .. el_label .. [[
</TD></TR>
]]
      else
        label = label .. " | <" .. n .. "> " .. el_label
      end
      n = n + 1
      handled[ i ] = true
    end
    -- and then the hash part
    local keys, values = {}, {}
    for k,v in pairs( tab ) do
      node.important = true
      if not handled[ k ] then -- skip array part elements
        local k_label = make_label( tab, k, data, id, "k"..n, depth )
        local v_label = make_label( tab, v, data, id, "v"..n, depth )
        if data.use_html then
          label = label .. [[
  <TR><TD PORT="k]] .. n .. [[">]] .. k_label .. [[
</TD><TD PORT="v]] .. n .. [[">]] .. v_label .. [[
</TD></TR>
]]
        else
          append( keys, "<k" .. n .. "> " .. k_label )
          append( values, "<v" .. n .. "> " .. v_label )
        end
        n = n + 1
      end
    end
    if data.use_html then
      node.label = label .. [[</TABLE>]]
    else
      if next( keys ) ~= nil then
        label = label .. " | { { " .. table.concat( keys, " | " ) ..
                " } | { " .. table.concat( values, " | " ) .. " } }"
      end
      node.label = label .. " }"
    end
    -- and now the metatable
    local mt = get_metatable( tab, data.show_metatables )
    if type( mt ) == "table" then
      local id2 = dottify_table( mt, data, depth+1 )
      dottify_metatable_ref( tab, id .. ":0", mt, id2 .. ":0", data )
    end
  end
  return data.node2id[ tab ]
end


function dottify_userdata( udata, data, depth )
  assert( type( udata ) == "userdata" )
  update_node_depth( udata, data, depth )
  if not data.node2id[ udata ] then
    local id = define_node( data, {
      value = udata,
      label = tostring( udata ),
      shape = "box"
    } )
    -- the metatable
    local mt = get_metatable( udata, data.show_metatables )
    if type( mt ) == "table" then
      local id2 = dottify_table( mt, data, depth+1 )
      dottify_metatable_ref( udata, id, mt, id2..":0", data )
    end
    -- the environment
    local env = get_environment( udata, data.show_environments )
    if type( env ) == "table" then
      local id2 = dottify_table( env, data, depth+1 )
      dottify_environment_ref( udata, id, env, id2..":0", data )
    end
  end
  return data.node2id[ udata ]
end


function dottify_thread( thread, data, depth )
  assert( type( thread ) == "thread" )
  update_node_depth( thread, data, depth )
  if not data.node2id[ thread ] then
    local id = define_node( data, {
      value = thread,
      label = tostring( thread ),
      shape = "triangle"
    } )
    -- the environment
    local env = get_environment( val, data.show_environments )
    if type( env ) == "table" then
      local id2 = dottify_table( env, data, depth+1 )
      dottify_environment_ref( thread, id, env, id2..":0", data )
    end
  end
  return data.node2id[ thread ]
end



function dottify_function( func, data, depth )
  assert( type( func ) == "function" )
  update_node_depth( func, data, depth )
  if not data.node2id[ func ] then
    local id = define_node( data, {
      value = func,
      label = tostring( func ),
      shape = "ellipse"
    } )
    -- the environment
    local env = get_environment( func, data.show_environments )
    if type( env ) == "table" then
      local id2 = dottify_table( env, data, depth+1 )
      dottify_environment_ref( func, id, env, id2..":0", data )
    end
    -- the upvalues
    if data.show_upvalues and
       type( debug ) == "table" and
       type( debug.getupvalue ) == "function" then
      local n = 1
      repeat
        local name, upvalue = debug.getupvalue( func, n )
        if type( upvalue ) == "table" then
          local id2 = dottify_table( upvalue, data, depth+1 )
          dottify_upvalue_ref( func, id, upvalue, id2..":0", data, name )
        elseif type( upvalue ) == "userdata" then
          local id2 = dottify_userdata( upvalue, data, depth+1 )
          dottify_upvalue_ref( func, id, upvalue, id2, data, name )
        elseif type( upvalue ) == "function" then
          local id2 = dottify_function( upvalue, data, depth+1 )
          dottify_upvalue_ref( func, id, upvalue, id2, data, name )
        elseif type( upvalue ) == "thread" then
          local id2 = dottify_thread( upvalue, data, depth+1 )
          dottify_upvalue_ref( func, id, upvalue, id2, data, name )
        end
        n = n + 1
      until name == nil
    end
  end
  return data.node2id[ func ]
end

local option_names = {
  "label", "shape", "style", "dir", "arrowhead", "arrowtail", "color",
  "fillcolor"
}

local function process_options( obj )
  local options = {}
  for _,opt in ipairs( option_names ) do
    if obj[ opt ] then
      local quote_on = "\""
      local quote_off = "\""
      if opt == "label" and type( obj[ opt ] ) == "string" and
         obj[ opt ]:match( "^<.*>$" ) then
        quote_on, quote_off = "<", ">"
      end
      append( options, tostring( opt ) .. "=" .. quote_on ..
                       tostring( obj[ opt ] ) .. quote_off )
    end
  end
  return options
end


local function write_nodes( file, data )
  for _,n in ipairs( data.nodes ) do
    if (data.max_depth <= 0 or
        data.node2depth[ n.value ] <= data.max_depth) and
       (data.show_unimportant or n.important) then
      local options = process_options( n )
      file:write( "  ", tostring( data.node2id[ n.value ] ),
                  " [", table.concat( options, "," ), "];\n" )
    end
  end
end


local function write_edges( file, data )
  for _,e in ipairs( data.edges ) do
    if (data.max_depth <= 0 or
        (data.node2depth[ e.A ] <= data.max_depth and
         data.node2depth[ e.B ] <= data.max_depth)) and
       (data.show_unimportant or
        (data.nodes[ data.node2id[ e.A ] ].important and
         data.nodes[ data.node2id[ e.B ] ].important)) then
      local id1 = e.A_id or data.node2id[ e.A ]
      local id2 = e.B_id or data.node2id[ e.B ]
      local options = process_options( e )
      file:write( "  ", tostring( id1 ), " -> ", tostring( id2 ),
                  " [", table.concat( options, "," ), "];\n" )
    end
  end
end


-- main function
local function dottify( filename, val, ... )
  local data = {
    n_nodes = 1,
    node2id = {},
    node2depth = {},
    nodes = {},
    edges = {},
    show_metatables = true,
    show_upvalues = true,
    show_environments = false,
    use_html = true,
    show_unimportant = false,
    max_depth = 0,
  }
  for i = 1, select( '#', ... ) do
    local opt = select( i, ... )
    if opt == "noenvironments" then
      data.show_environments = false
    elseif opt == "nometatables" then
      data.show_metatables = false
    elseif opt == "noupvalues" then
      data.show_upvalues = false
    elseif opt == "nohtml" then
      data.use_html = false
    elseif opt == "environments" then
      data.show_environments = true
    elseif opt == "metatables" then
      data.show_metatables = true
    elseif opt == "upvalues" then
      data.show_upvalues = true
    elseif opt == "html" then
      data.use_html = true
    elseif opt == "unimportant" then
      data.show_unimportant = true
    elseif type( opt ) == "number" then
      data.max_depth = opt
    end
  end
  local t = type( val )
  if t == "table" then
    local id = dottify_table( val, data, 1 )
    data.nodes[ id ].important = true
  elseif t == "function" then
    local id = dottify_function( val, data, 1 )
    data.nodes[ id ].important = true
  elseif t == "thread" then
    local id = dottify_thread( val, data, 1 )
    data.nodes[ id ].important = true
  elseif t == "userdata" then
    local id = dottify_userdata( val, data, 1 )
    data.nodes[ id ].important = true
  else
    io.stderr:write( "warning: unsuitable value for dotlua!\n" )
  end
  local file = assert( io.open( filename, "w" ) )
  file:write( "digraph {\n" )
  write_nodes( file, data )
  write_edges( file, data )
  file:write( "}\n" )
  file:close()
end

return dottify

