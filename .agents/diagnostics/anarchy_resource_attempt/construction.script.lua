local util = ug_require "::/scripts/util.tl"
local collision = ug_require "xiaom_no_collision::/collision_util.lua"

function data()
    return {
        -- This is the engine's BaseConfig.constructionScript entry point.
        -- Unlike a construction's updateScript it receives one context table.
        constructWithModules = function(params)
            local original = params.scriptParams.xiaomNoCollisionOriginal
            assert(original and type(original.fileName) == "string",
                "[xiaom_no_collision] missing original construction script")
            local runOriginal = util.useFn(original.fileName)
            assert(type(runOriginal) == "function",
                "[xiaom_no_collision] original construction script unavailable")

            local forwarded = {}
            for key, value in pairs(params) do forwarded[key] = value end
            forwarded.scriptParams = original.params
            return collision.clearConstruction(runOriginal(forwarded))
        end,
    }
end
