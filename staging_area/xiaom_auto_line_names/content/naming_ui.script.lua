function data()
    return {install=function(replacementApi)
        local ui=ug_require "xiaom_auto_line_names::/naming_ui.lua"
        ui.install(replacementApi)
    end}
end
