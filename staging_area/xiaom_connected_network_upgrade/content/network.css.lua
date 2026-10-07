local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
    local result = {}
    -- TF3 loads compiled rules with levels/styleSheet, rather than raw selectors.
    local add = ssu.makeAdder(result)
    -- stylesheetutil accepts letters, digits, hyphens and dots in selector IDs.
    local scope = "#xiaom-connected-network-upgrade-window"
    add(scope, {minSize = {540, -1}})
    add(scope .. " !network-upgrade-body", {
        padding = {12, 16, 12, 16}, innerSpacing = {8, 8},
    })
    add(scope .. " !network-upgrade-text", {
        textAutoWrap = true, maxSize = {600, -1},
    })
    add(scope .. " !network-upgrade-reasons", {
        minSize = {500, 60}, maxSize = {620, 220},
    })
    return result
end
