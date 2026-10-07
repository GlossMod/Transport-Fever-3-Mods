local ssu = require "::/gui/main/stylesheetutil.lua"
local color_util = require "::/gui/main/color_util.tl"
local transf = require "::/scripts/mat4.tl"
local vec3 = require "::/scripts/vec3.tl"

function data()
    local result = {}
    local add = ssu.makeAdder(result)
    local native = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
    local ink = {0.93, 0.96, 0.99, 1}
    local muted = {0.65, 0.72, 0.80, 1}
    local live = {0.38, 0.86, 0.76, 1}
    local load = {0.94, 0.76, 0.43, 1}
    local surface = {fileName = "::/gui/entity_window/design/card_surface.tga",
        horizontal = {0, 6, 26, 32}, vertical = {0, 6, 26, 32}}
    local contour = {fileName = "::/gui/entity_window/design/card_contour.tga",
        horizontal = {0, 6, 26, 32}, vertical = {0, 6, 26, 32}}

    add("R::XiaomGlobalTuningGameBar, R::XiaomGlobalTuningGameBar > FloatingLayout", {gravity = {-1, 1}})
    -- Match the small circular buttons in the native right-hand game bar.
    add("#xiaom-global-tuning-launcher", {
        gravity = {1, 1}, size = {28, 28}, minSize = {28, 28}, maxSize = {28, 28},
        margin = {0, 12, 88, 0}, padding = {1, 1, 1, 1},
        backgroundImage1 = {fileName = "::/gui/game_bar/design/tool_button/button_small_surface.tga"},
        backgroundColor1 = native.AccentVeryDark,
        borderImage = {fileName = ""}, borderColor = native.Invisible,
        shadowNinePatch = {fileName = "::/gui/game_bar/design/tool_button/button_small_shadow.tga"},
        shadowColor = native.NeutralVeryDark, shadowWidth = {2, 2, 2, 2},
        transformOrigin = {0.5, 0.5},
        transform = transf.scaleRotZTransl(1.0, 0.0, vec3.new(0.0, 0.0, 0.0)),
        transitionPropertyDuration = {["transform"] = 0.1},
    })
    add("#xiaom-global-tuning-launcher:hover", {
        backgroundColor1 = color_util.getHoverFromRaw(native.AccentLight),
        transform = transf.scaleRotZTransl(1.1, 0.0, vec3.new(0.0, 0.0, 0.0)),
    })
    add("#xiaom-global-tuning-launcher:active", {
        backgroundColor1 = color_util.getActiveFromRaw(native.AccentLight),
        transform = transf.scaleRotZTransl(1.0, 0.0, vec3.new(0.0, 0.0, 0.0)),
    })
    add("#xiaom-global-tuning-launcher !xiaom-tuning-launcher-icon", {
        size = {26, 26}, padding = {0, 0, 0, 0},
        backgroundImage1 = {fileName = "::/gui/game_bar/design/tool_button/button_small_surface.tga"},
        backgroundColor1 = native.NeutralLightest,
    })
    add("#xiaom-global-tuning-launcher !xiaom-tuning-launcher-icon > BoxLayout", {gravity = {0.5, 0.5}})
    add("#xiaom-global-tuning-launcher ImageView", {
        size = {20, 20}, minSize = {20, 20}, maxSize = {20, 20},
        gravity = {0.5, 0.5}, color = native.AccentVeryDark,
    })
    -- Unique classes also work when the native Window ID is attached to its
    -- container. Layout spacing uses innerSpacing, component spacing padding.
    add("Window!xiaom-tuning-window Window::Content", {padding = {0, 8, 8, 8}})
    add("Window!xiaom-tuning-window Window::Title", {fontSize = 18, color = ink})
    add("!xiaom-tuning-body", {
        size = {640, -1}, padding = {16, 20, 16, 20},
        backgroundColor = {0.06, 0.085, 0.12, 0.99}, color = ink,
    })
    add("!xiaom-tuning-body TextView", {color = ink, fontSize = 13})
    add("!xiaom-tuning-body-layout", {innerSpacing = {8, 8}, outerSpacing = {0, 0, 0, 0}, gravity = {-1, 0}})
    add("!xiaom-tuning-intro", {innerSpacing = {16, 0}, gravity = {-1, 0.5}})
    add("!xiaom-tuning-body !xiaom-tuning-heading", {size = {400, -1}, fontSize = 22})
    add("!xiaom-tuning-body !xiaom-tuning-autosave", {fontSize = 12, color = live, gravity = {1, 0.5}})
    add("!xiaom-tuning-body !xiaom-tuning-note", {fontSize = 12, color = muted, textAutoWrap = true, maxSize = {572, -1}})
    add("!xiaom-tuning-card", {
        padding = {10, 12, 10, 12}, backgroundImage1 = surface, borderImage = contour,
        backgroundColor1 = {0.105, 0.14, 0.185, 1}, borderColor = {0.23, 0.29, 0.36, 1},
    })
    add("!xiaom-tuning-card-layout", {innerSpacing = {10, 10}, outerSpacing = {0, 0, 0, 0}, gravity = {-1, 0}})
    add("!xiaom-tuning-card-heading", {innerSpacing = {10, 0}, gravity = {-1, 0.5}})
    add("!xiaom-tuning-body !xiaom-tuning-section", {size = {180, -1}, fontSize = 15, color = ink})
    add("!xiaom-tuning-body !xiaom-tuning-caption", {fontSize = 11, color = muted})
    add("!xiaom-tuning-field-pair", {innerSpacing = {16, 0}, gravity = {-1, 0}})
    add("!xiaom-tuning-field", {size = {280, -1}, padding = {0, 0, 0, 0}})
    add("!xiaom-tuning-field-layout", {innerSpacing = {4, 4}, gravity = {-1, 0}})
    add("!xiaom-tuning-field-heading", {innerSpacing = {0, 0}, gravity = {-1, 0.5}})
    add("!xiaom-tuning-label", {size = {188, -1}, fontSize = 13})
    add("!xiaom-tuning-body !xiaom-tuning-badge-live", {size = {92, -1}, fontSize = 11, color = live, textAlignment = {1, 0.5}})
    add("!xiaom-tuning-body !xiaom-tuning-badge-load", {size = {92, -1}, fontSize = 11, color = load, textAlignment = {1, 0.5}})
    add("!xiaom-tuning-choice", {size = {280, 32}, minSize = {280, 32}, maxSize = {280, 32}})
    add("!xiaom-tuning-choice TextView", {fontSize = 13, color = ink})
    add("!xiaom-tuning-status-panel", {padding = {8, 10, 8, 10}, backgroundImage1 = surface,
        backgroundColor1 = {0.065, 0.10, 0.145, 1}})
    add("!xiaom-tuning-status-layout", {innerSpacing = {4, 4}})
    add("!xiaom-tuning-body !xiaom-tuning-status", {fontSize = 12, color = ink, textAutoWrap = true, maxSize = {576, -1}})
    add("!xiaom-tuning-actions", {innerSpacing = {10, 0}, gravity = {-1, 0.5}})
    add("!xiaom-tuning-actions Button", {padding = {6, 14, 6, 14}, minSize = {106, 32}})
    add("!xiaom-tuning-body !xiaom-tuning-pending", {fontSize = 12, color = muted, margin = {0, 0, 0, 10}, gravity = {1, 0.5}})
    return result
end
