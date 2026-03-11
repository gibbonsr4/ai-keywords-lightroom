-- dkjson.lua - David Kolf's JSON module for Lua 4/5
-- Version 2.6, trimmed for plugin use (encode + decode only)
-- License: MIT  https://dkolf.de/dkjson/

local json = { version = "2.6" }

local escape_char_map = {
  ["\\"] = "\\\\", ["\""] = "\\\"", ["\b"] = "\\b",
  ["\f"] = "\\f",  ["\n"] = "\\n",  ["\r"] = "\\r", ["\t"] = "\\t",
}
local function escape_char(c)
  return escape_char_map[c] or string.format("\\u%04x", c:byte())
end
local function encode_string(val)
  return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end

local function encode_value(val, stack)
  local t = type(val)
  if t == "nil" then
    return "null"
  elseif t == "boolean" then
    return tostring(val)
  elseif t == "number" then
    if val ~= val then return "null" end -- NaN
    return string.format("%.14g", val)
  elseif t == "string" then
    return encode_string(val)
  elseif t == "table" then
    if stack[val] then error("circular reference") end
    stack[val] = true
    local result
    -- Detect array vs object
    local is_array = true
    local max_n = 0
    for k, _ in pairs(val) do
      if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
        is_array = false; break
      end
      if k > max_n then max_n = k end
    end
    if is_array and max_n == #val then
      local parts = {}
      for i = 1, #val do
        parts[i] = encode_value(val[i], stack)
      end
      result = "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      for k, v in pairs(val) do
        if type(k) == "string" then
          parts[#parts+1] = encode_string(k) .. ":" .. encode_value(v, stack)
        end
      end
      result = "{" .. table.concat(parts, ",") .. "}"
    end
    stack[val] = nil
    return result
  else
    error("unsupported type: " .. t)
  end
end

function json.encode(val)
  return encode_value(val, {})
end

-- ── Decoder ────────────────────────────────────────────────────────────────
local function skip_whitespace(s, i)
  return s:match("^%s*()", i)
end

local function decode_value(s, i)
  i = skip_whitespace(s, i)
  local c = s:sub(i, i)
  if c == '"' then
    -- String
    local j = i + 1
    local parts = {}
    while j <= #s do
      local ch = s:sub(j, j)
      if ch == '"' then
        return table.concat(parts), j + 1
      elseif ch == '\\' then
        local esc = s:sub(j+1, j+1)
        local map = {['"']='"',['\\']='\\',['/']='\/',['b']='\b',
                     ['f']='\f',['n']='\n',['r']='\r',['t']='\t'}
        if map[esc] then
          parts[#parts+1] = map[esc]; j = j + 2
        elseif esc == 'u' then
          local hex = s:sub(j+2, j+5)
          parts[#parts+1] = utf8_char(tonumber(hex, 16) or 63); j = j + 6
        else
          parts[#parts+1] = esc; j = j + 2
        end
      else
        parts[#parts+1] = ch; j = j + 1
      end
    end
    error("unterminated string at " .. i)
  elseif c == '{' then
    -- Object
    local obj = {}
    i = skip_whitespace(s, i + 1)
    if s:sub(i, i) == '}' then return obj, i + 1 end
    while true do
      local key; key, i = decode_value(s, i)
      i = skip_whitespace(s, i)
      if s:sub(i, i) ~= ':' then error("expected ':' at " .. i) end
      local val; val, i = decode_value(s, i + 1)
      obj[key] = val
      i = skip_whitespace(s, i)
      local sep = s:sub(i, i)
      if sep == '}' then return obj, i + 1 end
      if sep ~= ',' then error("expected ',' or '}' at " .. i) end
      i = skip_whitespace(s, i + 1)
    end
  elseif c == '[' then
    -- Array
    local arr = {}
    i = skip_whitespace(s, i + 1)
    if s:sub(i, i) == ']' then return arr, i + 1 end
    while true do
      local val; val, i = decode_value(s, i)
      arr[#arr+1] = val
      i = skip_whitespace(s, i)
      local sep = s:sub(i, i)
      if sep == ']' then return arr, i + 1 end
      if sep ~= ',' then error("expected ',' or ']' at " .. i) end
      i = skip_whitespace(s, i + 1)
    end
  elseif s:sub(i, i+3) == 'true'  then return true,  i + 4
  elseif s:sub(i, i+4) == 'false' then return false, i + 5
  elseif s:sub(i, i+3) == 'null'  then return nil,   i + 4
  else
    -- Number
    local num_str = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
    if num_str then return tonumber(num_str), i + #num_str end
    error("unexpected token '" .. c .. "' at position " .. i)
  end
end

-- Minimal UTF-8 helper (handles BMP codepoints)
utf8_char = function(cp)
  if cp < 0x80 then return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp/64), 0x80 + cp%64)
  else
    return string.char(0xE0 + math.floor(cp/4096),
                       0x80 + math.floor(cp/64)%64,
                       0x80 + cp%64)
  end
end

function json.decode(s)
  local val, _ = decode_value(s, 1)
  return val
end

return json
