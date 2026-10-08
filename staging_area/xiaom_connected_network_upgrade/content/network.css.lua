local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
    local result = {}
    local add = ssu.makeAdder(result)
    local scope = "#xiaom-connected-network-upgrade-window "
    local function style(selector, values) add(scope .. selector, values) end
    local ink = {0.91, 0.95, 0.98, 1}
    local muted = {0.62, 0.70, 0.78, 1}
    local accent = {0.40, 0.77, 1, 1}
    local success = {0.47, 0.84, 0.67, 1}
    local warning = {0.98, 0.77, 0.42, 1}
    local danger = {1, 0.52, 0.51, 1}
    local surface = {
        fileName = "::/gui/entity_window/design/card_surface.tga",
        horizontal = {0, 6, 26, 32}, vertical = {0, 6, 26, 32},
    }
    local contour = {
        fileName = "::/gui/entity_window/design/card_contour.tga",
        horizontal = {0, 6, 26, 32}, vertical = {0, 6, 26, 32},
    }
    local function card(class, color, spacing)
        style("!" .. class, {
            padding = {10, 12, 10, 12}, backgroundImage1 = surface, backgroundColor1 = color,
            borderImage = contour, borderColor = {0.23, 0.31, 0.39, 1},
        })
        -- Spacing belongs to the real child layout, not just its component.
        style("!" .. class .. " > BoxLayout", {innerSpacing = {spacing or 5, spacing or 5}})
    end

    add("Window#xiaom-connected-network-upgrade-window Window::Content", {padding = {0, 8, 8, 8}})
    add("Window#xiaom-connected-network-upgrade-window Window::Title", {fontSize = 18, color = ink})
    style("!network-content", {
        size = {720, -1}, padding = {12, 16, 12, 16}, backgroundColor = {0.075, 0.105, 0.14, 1},
    })
    style("!network-content > BoxLayout", {innerSpacing = {9, 9}})
    style("!network-main-scroll", {size = {688, 520}})
    style("!network-body", {padding = {0, 10, 0, 0}})
    style("!network-body > BoxLayout", {innerSpacing = {9, 9}})
    style("!network-text", {fontSize = 14, color = ink, textAutoWrap = true, maxSize = {640, -1}})
    style("!network-caption", {fontSize = 12, color = muted})
    style("!network-note", {fontSize = 12, color = muted})
    style("!network-ink", {color = ink})
    style("!network-muted", {color = muted})
    style("!network-accent", {color = accent})
    style("!network-success", {color = success})
    style("!network-warning", {color = warning})
    style("!network-danger", {color = danger})

    card("network-target", {0.105, 0.19, 0.265, 1})
    style("!network-target", {borderColor = {0.23, 0.48, 0.65, 1}})
    style("!network-target-name", {fontSize = 20})
    card("network-status", {0.115, 0.155, 0.195, 1}, 7)
    style("!network-status-text", {fontSize = 14})
    style("!network-progress", {size = {620, 22}})
    style("!network-metric-row > BoxLayout", {innerSpacing = {10, 0}})
    card("network-metric", {0.105, 0.145, 0.185, 1}, 3)
    style("!network-metric", {size = {188, -1}, padding = {8, 12, 8, 12}})
    style("!network-metric !network-text", {maxSize = {164, -1}})
    style("!network-number", {fontSize = 24})
    card("network-cost", {0.105, 0.145, 0.185, 1}, 4)
    style("!network-price", {fontSize = 23})

    card("network-reasons", {0.16, 0.145, 0.115, 1}, 6)
    style("!network-section-title", {fontSize = 13, color = warning})
    style("!network-reason-heading > BoxLayout", {innerSpacing = {12, 0}, gravity = {-1, 0.5}})
    style("!network-detail-toggle", {padding = {3, 10, 3, 10}, minSize = {-1, 26}})
    style("!network-detail-toggle !network-text", {fontSize = 12})
    style("!network-reason-content", {padding = {0, 10, 0, 0}})
    style("!network-reason-content > BoxLayout", {innerSpacing = {5, 5}})
    style("!network-reason", {fontSize = 12, maxSize = {615, -1}})
    style("!network-error-item", {padding = {6, 8, 6, 8}, backgroundColor = {0.11, 0.105, 0.09, 1}})
    style("!network-error-item > BoxLayout", {innerSpacing = {3, 3}})
    style("!network-error-item !network-text", {fontSize = 12, maxSize = {590, -1}})

    style("!network-actions > BoxLayout", {innerSpacing = {10, 0}, gravity = {-1, 0.5}})
    style("!network-button", {minSize = {-1, 34}, padding = {6, 14, 6, 14}})
    style("Button:disabled !network-text", {color = {0.43, 0.48, 0.52, 1}})
    return result
end
