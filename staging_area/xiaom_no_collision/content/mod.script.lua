local anarchy = ug_require "xiaom_no_collision::/anarchy_util.lua"

function data()
    return {
        installAnarchyUI = function(_replacementApi)
            anarchy.installUI()
        end,
    }
end
