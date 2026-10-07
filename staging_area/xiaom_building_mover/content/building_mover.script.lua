function data()
    return {
        installDetailButton = function(replacementApi)
            -- Invoked by TF3's GUI bootstrap before any recipes are rendered.
            local details = ug_require "xiaom_building_mover::/detail_button.lua"
            details.install(replacementApi)
        end,
    }
end
