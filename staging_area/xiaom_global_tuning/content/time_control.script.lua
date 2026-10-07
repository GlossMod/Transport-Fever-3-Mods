local controller

function data()
    local initialized = false
    return {
        guiUpdate = function(_captureParams, _state, _guiState)
            local world = api.engine.util.getWorld()
            if world == nil or world < 0 or not api.engine.entityExists(world) then return end
            if not api.engine.getComponent(world, api.type.ComponentType.GAME_SPEED) then return end
            if not controller then controller = ug_require "xiaom_global_tuning::/tuning_controller.lua" end
            if not initialized then
                initialized = true
                controller.initialize(true)
            end
            controller.update()
        end,
    }
end
