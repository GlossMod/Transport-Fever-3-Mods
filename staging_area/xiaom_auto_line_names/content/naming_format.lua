local U=ug_require "xiaom_auto_line_names::/naming_util.lua"
local M={}
local codes={bus="B",truck="R",tram="Tr",train="T",ship="W",aircraft="A",helicopter="H"}
local cargoCodes={coal="COAL",iron_ore="IRON",crude_oil="OIL",oil="OIL",fuel="FUEL",grain="GRAIN",logs="LOG",planks="PLK",
    steel="STL",stone="STN",construction_materials="MAT",tools="TOOL",machines="MACH",goods="GOOD",food="FOOD",livestock="LIVE",
    books="BOOK",bricks="BRK",chemicals="CHEM",clay="CLAY",clothes="CLTH",fabric="FAB",furniture="FURN",glass="GLS",
    paper="PAP",plastic="PLAS",rubber="RUB",tinned_food="TIN",tires="TIRE",wool="WOOL"}
local shorts={zh_CN={coal="煤",iron_ore="铁矿",crude_oil="原油",construction_materials="建材"},
    en={construction_materials="Materials",iron_ore="Iron",crude_oil="Oil",chemicals="Chem",clothes="Clth",furniture="Furn",tinned_food="Tinned"}}
function M.cargo(items,config)
    local result,seen={},{}
    for _,item in ipairs(items) do
        local override=config.cargoOverrides[item.resource] or config.cargoOverrides[item.key] or {}
        local label=override[config.cargoStyle]
        if not label and config.cargoStyle == "short" then label=(shorts[config.language] or {})[item.key] end
        if not label and config.cargoStyle == "code" then label=cargoCodes[item.key] end
        label=label or item.name or config.label.unknown
        if not seen[label] then result[#result+1]=label; seen[label]=true end
    end
    local total=#result
    for i=total,config.cargoLimit+1,-1 do result[i]=nil end
    local s=#result>0 and table.concat(result,config.label.join) or config.label.pending
    if total>config.cargoLimit then s=s .. "+" .. (total-config.cargoLimit) end
    return s
end
function M.name(info,number,config)
    local l=config.label
    local goods=info.kind ~= "passengers"
    local cargo=goods and M.cargo(info.cargo,config) or ""
    local num=string.format("%0" .. config.numberWidth .. "d",number)
    local region=config.region and info.region ~= "" and (info.region .. " ") or ""
    local prefix=region .. l[info.transport] .. l.space .. l[info.kind]
    if config.format == "classic" then
        return "[" .. l[info.kind] .. "] " .. (goods and cargo .. "-" or "") .. info.placeA .. "-" .. info.placeB
    elseif config.format == "compact" then
        return "[" .. region .. codes[info.transport] .. (info.kind == "passengers" and "P" or info.kind == "goods" and "C" or "M") .. num .. "] " ..
            (goods and cargo .. "-" or "") .. U.short(info.placeA,config.shortLength) .. "-" .. U.short(info.placeB,config.shortLength)
    elseif config.format == "custom" then
        local values={transportType=l[info.transport] .. l.space,serviceType=l[info.kind],cargoTypes=cargo,
            placeA=info.placeA,placeB=info.placeB,lineType=info.region,lineNumber=num}
        local template=goods and config.freightTemplate or config.passengerTemplate
        return template:gsub("{([%w_]+)}",function(key) return values[key] or "" end)
    end
    return "[" .. prefix .. "] " .. (goods and cargo .. "-" or "") .. info.placeA .. "-" .. info.placeB .. "-" .. num
end
return M
