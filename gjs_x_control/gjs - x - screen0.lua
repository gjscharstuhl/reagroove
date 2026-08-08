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
        -- Copy Main's current track/region selection into Edit only when
        -- entering Edit. Edit may then change its own selection independently.
        local state = api.get_screen_state and api.get_screen_state(0) or nil
        local track_note = state and state.radio and state.radio["tracks"] or 11
        local region_note = state and state.radio and state.radio["regions"] or 61

        local previous = api._screen0_edit_entry or {}
        api._screen0_edit_entry = {
            track = math.max(1, math.min(8, (tonumber(track_note) or 11) - 10)),
            region = math.max(1, math.min(8, (tonumber(region_note) or 61) - 60)),
            serial = (tonumber(previous.serial) or 0) + 1
        }

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
    
    reaper.gmem_attach("GJS_X_BRIDGE")
	reaper.gmem_write(1000, 1)
end
