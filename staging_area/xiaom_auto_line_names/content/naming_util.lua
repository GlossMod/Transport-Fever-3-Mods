local M = {}
function M.copy(t)
    if type(t) ~= "table" then return t end
    local r = {}; for k, v in pairs(t) do r[k] = M.copy(v) end; return r
end
function M.clean(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[\r\n\t]", " "):match("^%s*(.-)%s*$")
    return s ~= "" and s or nil
end
function M.short(s, n)
    local result, count = {}, 0
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1; if count > n then break end; result[#result + 1] = ch
    end
    return table.concat(result)
end
-- Stable serialization is used as a revision token, never as executable code.
function M.signature(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys = {}; for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    local r = {}; for _, k in ipairs(keys) do r[#r + 1] = M.signature(k) .. "=" .. M.signature(value[k]) end
    return "{" .. table.concat(r, ";") .. "}"
end
function M.report(s) debugPrint("[xiaom_auto_line_names] " .. tostring(s)) end
return M
