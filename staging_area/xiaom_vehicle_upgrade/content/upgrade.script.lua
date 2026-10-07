function data()
    return {
        install = function(replacementApi)
            local entry = ug_require "xiaom_vehicle_upgrade::/upgrade_entry.lua"
            entry.install(replacementApi)
        end,
    }
end
