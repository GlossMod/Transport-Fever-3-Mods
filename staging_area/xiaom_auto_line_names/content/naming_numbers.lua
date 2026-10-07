local M = {}
function M.assign(entry, counters, category)
    if entry.category ~= category or not entry.number then
        local number=(counters[category] or 0)+1
        counters[category]=number; entry.category=category; entry.number=number
    end
    return entry.number
end
return M
