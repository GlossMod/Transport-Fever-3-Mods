function data()
    return {
        installGui = function(replacementApi)
            local ui = ug_require "xiaom_global_tuning::/tuning_ui.lua"
            ui.install(replacementApi)
        end,
    }
end
