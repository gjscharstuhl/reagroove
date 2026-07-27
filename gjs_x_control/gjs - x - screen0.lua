-- ============================================================
-- Screen 0: main/edit container
-- ============================================================

local draw_main = include("gjs - x - mainscreen.lua")
local draw_edit = include("gjs - x - edit.lua")

local current_view = "main"

return function(api)
    local function open_main()
        current_view = "main"
        api.redraw()
    end

    local function open_edit()
        current_view = "edit"
        api.redraw()
    end

    local navigation = {
        open_main = open_main,
        open_edit = open_edit
    }

    if current_view == "edit" then
        draw_edit(api, navigation)
    else
        draw_main(api, navigation)
    end
end
