local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
    local result = {}
    local add = ssu.makeAdder(result)
    local scope = "#xiaom-vehicle-upgrade-window "
    local ink = {0.91, 0.94, 0.97, 1}
    local muted = {0.61, 0.69, 0.77, 1}
    local accent = {0.40, 0.73, 1, 1}
    local line = {0.25, 0.32, 0.39, 1}
    local surface = {
        fileName = "::/gui/entity_window/design/card_surface.tga",
        horizontal = {0, 6, 26, 32}, vertical = {0, 6, 26, 32},
    }
    local contour = {
        fileName = "::/gui/entity_window/design/card_contour.tga",
        horizontal = {0, 6, 26, 32}, vertical = {0, 6, 26, 32},
    }
    local function style(selector, values) add(scope .. selector, values) end

    add("R::XiaomUpgradeVehicleTab, !upgrade-vehicle-tab", {gravity = {-1, -1}, size = {-1, -1}})
    add("!upgrade-tab-toolbar", {gravity = {1, 0}, margin = {4, 8, 8, 8}})
    add("!upgrade-original-list", {gravity = {-1, -1}, size = {-1, -1}})
    add("#xiaom-vehicle-upgrade-button", {padding = {6, 14, 6, 14}})

    -- Paint an opaque component inside the native frame, keeping its controls.
    add("Window#xiaom-vehicle-upgrade-window Window::Content", {padding = {0, 8, 8, 8}})
    add("Window#xiaom-vehicle-upgrade-window Window::Title", {fontSize = 18, color = ink})
    style("!upgrade-content", {size = {920, -1}, padding = {12, 16, 12, 16},
        innerSpacing = {8, 8}, backgroundColor = {0.105, 0.14, 0.175, 1}, color = ink})
    style("TextView", {color = ink})
    style("!upgrade-intro", {innerSpacing = {4, 4}, margin = {0, 0, 4, 0}})
    style("!upgrade-heading", {fontSize = 18})
    style("!upgrade-note", {fontSize = 12, color = muted, textAutoWrap = true, maxSize = {830, -1}})
    style("!upgrade-caption", {fontSize = 11, color = muted})

    style("!upgrade-filters", {innerSpacing = {10, 0}})
    style("!upgrade-filter-field", {innerSpacing = {4, 4}})
    style("!upgrade-carrier-filter", {size = {154, 32}})
    style("!upgrade-line-filter", {size = {280, 32}})
    style("!upgrade-search", {size = {434, 32}})
    style("!upgrade-toolbar", {innerSpacing = {8, 0}, margin = {2, 0, 0, 0}})
    style("!upgrade-button", {padding = {5, 10, 5, 10}, minSize = {-1, 30}})
    style("!upgrade-results-count", {size = {186, -1}, gravity = {-1, 0.5}, fontSize = 12, color = muted})
    style("!upgrade-page-button", {padding = {5, 8, 5, 8}})
    style("!upgrade-page-number", {size = {44, -1}, gravity = {0.5, 0.5}, fontSize = 12, color = muted})

    style("!upgrade-scroll", {size = {-1, 360}, gravity = {-1, 0}, margin = {2, 0, 2, 0}})
    style("!upgrade-scroll-content", {gravity = {-1, 0}, padding = {0, 8, 0, 0}, innerSpacing = {10, 10}})
    style("!upgrade-group", {gravity = {-1, 0}, padding = {10, 12, 10, 12}, innerSpacing = {8, 8},
        backgroundImage1 = surface, backgroundColor1 = {0.15, 0.195, 0.235, 1}, borderImage = contour, borderColor = line})
    style("!upgrade-group-heading", {innerSpacing = {8, 0}})
    style("!upgrade-group-toggle", {gravity = {-1, 0.5}, padding = {2, 0, 2, 0},
        backgroundColor1 = {0, 0, 0, 0}, borderColor = {0, 0, 0, 0}})
    style("!upgrade-group-toggle TextView", {fontSize = 14, textAutoWrap = true, maxSize = {620, -1}})
    style("!upgrade-group-count", {size = {148, -1}, gravity = {1, 0.5}, fontSize = 12, color = muted})
    style("!upgrade-group-toggle:hover TextView", {color = accent})
    style("!upgrade-comparison", {gravity = {-1, 0}, innerSpacing = {10, 0}})
    style("!upgrade-model-card", {gravity = {-1, -1}, padding = {8, 10, 8, 10}, innerSpacing = {4, 4},
        backgroundImage1 = surface, backgroundColor1 = {0.105, 0.145, 0.18, 1}})
    style("!upgrade-target-card", {backgroundColor1 = {0.13, 0.205, 0.275, 1}, borderImage = contour,
        borderColor = {0.24, 0.43, 0.59, 1}})
    style("!upgrade-target-card !upgrade-caption", {color = accent})
    style("!upgrade-model-name", {fontSize = 14, textAutoWrap = true, maxSize = {378, -1}})
    style("!upgrade-model-body", {innerSpacing = {10, 0}, gravity = {-1, 0.5}})
    style("!upgrade-model-icon", {size = {96, 28}, gravity = {0, 0.5}})
    style("!upgrade-model-metrics", {fontSize = 12, textAutoWrap = true, maxSize = {268, -1}, color = muted})
    style("!upgrade-target-line", {innerSpacing = {8, 0}})
    style("!upgrade-target-label", {size = {48, -1}, gravity = {0, 0.5}, color = muted, fontSize = 12})
    style("!upgrade-target", {size = {780, 32}})
    style("!upgrade-unit !upgrade-target", {size = {792, 32}})

    style("!upgrade-vehicle-row", {gravity = {-1, 0}, padding = {8, 10, 8, 10}, innerSpacing = {4, 4},
        backgroundImage1 = surface, backgroundColor1 = {0.115, 0.155, 0.19, 1}})
    style("!upgrade-selected", {borderImage = contour, borderColor = {0.25, 0.45, 0.61, 1}})
    style("!upgrade-row-header, " .. scope .. "!upgrade-actions", {innerSpacing = {8, 0}, gravity = {-1, 0.5}})
    style("!upgrade-disclosure", {gravity = {-1, 0.5}, padding = {2, 0, 2, 0},
        backgroundColor1 = {0, 0, 0, 0}, borderColor = {0, 0, 0, 0}})
    style("!upgrade-disclosure TextView", {fontSize = 13, textAutoWrap = true, maxSize = {704, -1}})
    style("!upgrade-disclosure:hover TextView", {color = accent})
    style("!upgrade-row-name", {fontSize = 13})
    style("!upgrade-row-line", {fontSize = 11, color = muted, margin = {0, 0, 0, 28}, textAutoWrap = true, maxSize = {756, -1}})
    style("!upgrade-row-price", {fontSize = 12, margin = {0, 0, 0, 28}, textAutoWrap = true, maxSize = {756, -1}})
    style("!upgrade-status", {fontSize = 11, gravity = {1, 0.5}})
    style("!upgrade-unit", {padding = {8, 8, 8, 8}, innerSpacing = {6, 6}, margin = {4, 0, 0, 0}})
    style("!upgrade-subheading", {fontSize = 13, color = accent})
    style("!upgrade-warning-box", {padding = {6, 10, 6, 10}, backgroundImage1 = surface,
        backgroundColor1 = {0.27, 0.215, 0.135, 1}})
    style("!upgrade-warning", {fontSize = 12, color = {1, 0.78, 0.42, 1}, textAutoWrap = true, maxSize = {804, -1}})
    style("!upgrade-info-box", {padding = {6, 10, 6, 10}})
    style("!upgrade-error-section", {padding = {10, 12, 10, 12}, innerSpacing = {6, 6},
        backgroundImage1 = surface, backgroundColor1 = {0.225, 0.19, 0.155, 1}})
    style("!upgrade-error-row", {padding = {6, 8, 6, 8}, innerSpacing = {2, 2}})
    style("!upgrade-empty", {padding = {48, 20, 48, 20}, innerSpacing = {10, 10}, gravity = {-1, 0}})
    style("!upgrade-empty-title", {fontSize = 17, color = muted})

    style("!upgrade-summary", {padding = {10, 12, 10, 12}, innerSpacing = {8, 8},
        backgroundImage1 = surface, backgroundColor1 = {0.15, 0.20, 0.25, 1}, borderImage = contour, borderColor = line})
    style("!upgrade-invoice", {innerSpacing = {8, 0}})
    style("!upgrade-summary-metric", {size = {156, -1}, innerSpacing = {3, 3}})
    style("!upgrade-final-metric", {size = {224, -1}})
    style("!upgrade-number", {fontSize = 17})
    style("!upgrade-net", {fontSize = 21, color = accent})
    style("!upgrade-operator", {size = {24, -1}, gravity = {0.5, 0.5}, fontSize = 18, color = muted})
    style("!upgrade-selection-count", {fontSize = 13, color = muted, gravity = {1, 0.5}, textAutoWrap = true, maxSize = {184, -1}})
    style("!upgrade-summary-actions", {innerSpacing = {8, 0}, gravity = {-1, 0.5}})
    style("!upgrade-balance", {size = {560, -1}, gravity = {-1, 0.5}, fontSize = 12, color = muted})
    style("#xiaom-upgrade-confirm", {minSize = {164, 34}, padding = {6, 14, 6, 14}})
    style("#xiaom-upgrade-close", {minSize = {72, 34}, padding = {6, 12, 6, 12}})
    style("!upgrade-footnote", {fontSize = 11, color = muted, textAutoWrap = true, maxSize = {844, -1}})
    style("!upgrade-footer-blocked", {fontSize = 12, color = {1, 0.78, 0.42, 1}, textAutoWrap = true, maxSize = {844, -1}})
    style("!upgrade-message", {fontSize = 11, color = muted, textAutoWrap = true, maxSize = {870, -1}, margin = {0, 2, 0, 2}})
    style("!upgrade-balance!upgrade-warning", {color = {1, 0.78, 0.42, 1}})
    style("!upgrade-selection-count!upgrade-warning", {color = {1, 0.78, 0.42, 1}})
    style("Button:disabled TextView", {color = {0.45, 0.51, 0.57, 1}})
    -- Spacing belongs to the actual layout below each surface component.
    style("!upgrade-content > BoxLayout", {innerSpacing = {8, 8}})
    style("!upgrade-group > BoxLayout", {innerSpacing = {8, 8}})
    style("!upgrade-model-card > BoxLayout", {innerSpacing = {4, 4}})
    style("!upgrade-scroll-content > BoxLayout", {innerSpacing = {10, 10}})
    style("!upgrade-vehicle-row > BoxLayout", {innerSpacing = {4, 4}})
    style("!upgrade-unit > BoxLayout", {innerSpacing = {6, 6}})
    style("!upgrade-summary > BoxLayout", {innerSpacing = {8, 8}})
    style("!upgrade-summary-metric > BoxLayout", {innerSpacing = {3, 3}})
    style("!upgrade-error-section > BoxLayout", {innerSpacing = {6, 6}})
    style("!upgrade-empty > BoxLayout", {innerSpacing = {10, 10}})
    style("!upgrade-success", {color = {0.47, 0.83, 0.65, 1}})
    return result
end
