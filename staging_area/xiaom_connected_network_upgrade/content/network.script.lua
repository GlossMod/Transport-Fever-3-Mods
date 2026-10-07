function data()
    return {
        install = function(replacementApi)
            local entry = ug_require "xiaom_connected_network_upgrade::/network_entry.lua"
            entry.install(replacementApi)
        end,
    }
end
