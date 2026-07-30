-- lua/vehicle/extensions/auto/htmlTools.lua
local M = {}

--
--	START OF COPIED CODE (David Manura, MIT License)
--

local coroutine = coroutine
local next = next
local pairs = pairs
local string = string
local tostring = tostring
local type = type
local _G = _G
local io = io
local table = table

local format = string.format

-- Escape string to make suitable for embedding in HTML.
local function htmlize(s)
  s = s:gsub('&', '&amp;')
  s = s:gsub('<', '&lt;')
  s = s:gsub('>', '&gt;')
  return s
end

-- iterator function for table pairs.
-- hash part, then array part.
-- used for display.
local function table_pairs(t)
  local keys = {}
  for k in pairs(t) do keys[#keys+1] = k end
  
  -- Prevent crashes when sorting tables with non-comparable key types (tables, functions, etc.)
  table.sort(keys, function(a,b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then
      return ta < tb -- Sort by type name if types are different
    elseif ta == 'number' or ta == 'string' then
      return a < b   -- Safe direct comparison for primitives
    else
      return tostring(a) < tostring(b) -- Safe string fallback for complex types
    end
  end)
  
  local i = 0
  return function()
    i = i + 1
    local k = keys[i]
    if k then return k, t[k] end
  end
end

-- Serialize object o.  Writes one or more substrings to function append.
local function obj_serialize(o, append)
  if type(o) == 'table' then
    append('{')
    for k,v in table_pairs(o) do
      append('[')
      obj_serialize(k, append)
      append(']=[')
      obj_serialize(v, append)
      append('];')
    end
    append('}')
  elseif type(o) == 'string' then
    append(string.format('%q', o))
  else
    append(tostring(o))
  end
end

-- Returns serialization of o, not exceeding maxlen characters.
local function obj_tostring_short(o, maxlen)
  local s = ''
  local function append(ss)
    s = s .. ss
    if #s > maxlen then
      s = s:sub(1,maxlen) .. '...'
      coroutine.yield()
    end
  end
  local f = coroutine.wrap(obj_serialize)
  f(o, append)
  return s
end

local function analyze_tree(o)
  local ids = {}
  local current_id = 0
  local count = {}
  local from = {}

  local function analyze_tree_helper(o)
    if type(o) == 'table' then
      if count[o] then
        count[o] = count[o] + 1
      else
        count[o] = 1
        current_id = current_id + 1
        ids[o] = current_id
  
        local this_id = current_id
        for k,v in pairs(o) do
          analyze_tree_helper(k)
          analyze_tree_helper(v)
          if type(k) == 'table' then
            from[k] = from[k] or {}; from[k][o] = this_id .. '.' .. ids[k]
          end
          if type(v) == 'table' then
            from[v] = from[v] or {};
            from[v][o] = this_id .. '.' .. (ids[k] or tostring(k))
          end
        end
      end
    end
  end
  analyze_tree_helper(o)

  for k,v in pairs(count) do
    if v == 1 then count[k] = nil end
  end

  return ids, count, from
end

local header = [[
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en">
<head>
<title>FIX</title>
<style type="text/css">
.table {margin-left:1em; border: 1px solid black}
.table_row {border: 1px solid black}
</style>
<script type="text/javascript"><!--
function toggle(id) {
  if (document.getElementById) {
    var ele = document.getElementById(id);
    if (ele && ele.style) {
      ele.style.display = ele.style.display == 'none' ? '' : 'none';
    }
  }
}
function show_node(ele) {
  if (ele.style) {
    ele.style.display = '';
    if (ele.parentNode) show_node(ele.parentNode);
  }
}
function show(id) {
  if (document.getElementById) {
    var ele = document.getElementById(id);
    if (ele) show_node(ele);
  }
}
//--></script>
</head>
<body>
]]
local footer = [[</body></html>]]

-- Safe Logging Fallback (Allows execution outside of the BeamNG sandbox)
local function logSafe(level, category, message)
  if log then
    log(level, category, message)
  else
    print(string.format("[%s][%s] %s", level, category, message))
  end
end

-- Writes HTML representations of object o as one or more strings to
-- function output.
local function object_to_html(o, output)
  local ids, count, from = analyze_tree(o)

  local function output_header_html(o)
    if type(o) == 'table' then
      output(format('<a name="id%s"></a>', ids[o]))

      local is_empty = next(o) == nil
      output(is_empty and '(empty)' or
             '<a href="javascript:toggle(\'id' .. ids[o] .. '\')">[+]</a>')
      output(format([[Table ID %s]], ids[o]))
      output(type(o.tag) == 'string' and ' [Tag=' .. o.tag .. ']' or '')
      output(' ')
      output(htmlize(obj_tostring_short(o, 40)))
    elseif type(o) == 'string' then
      output(htmlize(string.format('%q', o)))
    else
      output(htmlize(tostring(o)))
    end  
  end

  local function output_body_html(o)
    if type(o) == 'table' then
      output(format('<div class="table" style="display:none" id="id%s">\n', ids[o]))

      -- xref
      if from[o] and next(from[o]) and next(from[o], next(from[o])) then
        output('<div>Referenced from: ')
        for _,from_id in pairs(from[o]) do
          output(format([[ <a onclick="show('id%s')" href="#id%s">%s</a> ]],
                 from_id, from_id, from_id))
        end
        output('</div>')
      end

      -- key/values
      for k,v in table_pairs(o) do
        local function prepare_output(oo)
          local f, is_long
          if count[oo] then
            f = function()
              output(format([[<a onclick="show('id%s')" href="#id%s">(see %s)</a>]],
                            ids[oo],ids[oo],ids[oo]))
            end
          elseif type(oo) ~= 'table' then
            f = function() output_header_html(oo) end
          else
            f = function() output_header_html(oo) end
            is_long = true
          end
          return f, is_long
        end
        local kf, klong = prepare_output(k)
        local vf, vlong = prepare_output(v)

        local field_id = ids[o] .. '.' .. (ids[k] or tostring(k))
        output(format([[<a name="id%s"></a>]], field_id))

        output(format('<div class="table_row" id="id%s">\n', field_id))
        kf()
        output('=')
        vf()
        if vlong then output_body_html(v) end
        output('</div>')
      end

      output('</div>\n')

    end
  end

  local function output_html(o)
    output('<div>')
    output_header_html(o)
    output('</div>')
    output_body_html(o)
  end

  logSafe("D", "htmlTools", "Writing general header...")
  output(header)

  logSafe("D", "htmlTools", "Writing contents...")
  output_html(o)
  for oo in pairs(count) do
    if oo ~= o then
      output_html(oo)
    end
  end

  logSafe("D", "htmlTools", "Writing footer...")
  output(footer)
end

--
--	END OF COPIED CODE
--

--[[ Dumps the contents to the console ]]--
local function dump(obj)
  -- Safely fall back to print() if standard output is sandboxed
  if io and io.stdout and type(io.stdout.write) == 'function' then
    object_to_html(obj, function(s) io.stdout:write(s) end)
  else
    object_to_html(obj, function(s) print(s) end)
  end
end

--[[ Writes the contents to the file with the specified name ]]--
local function dumpToFile(obj, filename)
  -- High Performance array collection of substrings (Bypasses GC-heavy quadratic string allocations)
  local parts = {}
  object_to_html(obj, function(s)
    parts[#parts + 1] = s
  end)
  local str = table.concat(parts)
  local fullFilename = filename .. ".html"
  
  -- PLATFORM INTEGRATION: Check for native BeamNG virtual file system writer
  if type(writeFile) == "function" then
    writeFile(fullFilename, str)
  elseif io and type(io.open) == "function" then
    local f = io.open(fullFilename, "w")
    if f then
      f:write(str)
      f:close()
    else
      logSafe("E", "htmlTools", "Failed to open file: " .. fullFilename)
    end
  else
    logSafe("W", "htmlTools", "Both io.open and writeFile are unavailable in this environment. Cannot dump: " .. fullFilename)
  end
end

M.dump			= dump
M.dumpToFile	= dumpToFile

return M