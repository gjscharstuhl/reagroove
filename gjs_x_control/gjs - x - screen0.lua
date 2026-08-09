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

        local main_track = math.max(1, math.min(8, (tonumber(track_note) or 11) - 10))
        local main_region = math.max(1, math.min(8, (tonumber(region_note) or 61) - 60))

        -- Prefer the pattern module's actual selected/queued pattern.
        -- This keeps Edit in sync even when Main's visible radio state is
        -- not the source that last changed the pattern.
        local pattern_region = nil
        if api.pattern
        and type(api.pattern.get_selected_region) == "function" then
            pattern_region = api.pattern.get_selected_region(main_track)
        end
        pattern_region = math.max(1, math.min(8, tonumber(pattern_region) or main_region))

        local previous = api._screen0_edit_entry or {}
        api._screen0_edit_entry = {
            track = main_track,
            region = pattern_region,
            pattern = pattern_region,
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
