-- ============================================================
-- gjs - x - screen1.lua
-- Pattern launcher
--
-- Elke rij is één track/projecttab.
-- Elke kolom is één region.
-- ============================================================
local scene_api = include("gjs - scene_api.lua")

return function(api)
    local C = api.COLOR

    -- Lege patterns blijven herkenbaar aan hun trackkleur, maar veel donkerder.
    -- Een pattern geldt als gevuld zodra er ergens in de bijbehorende region
    -- een media-item staat (op om het even welke track van het subproject).
    local EMPTY_BRIGHTNESS = 0.12

    local function dim_rgb(rgb, factor)
        return {
            math.floor((rgb[1] or 0) * factor + 0.5),
            math.floor((rgb[2] or 0) * factor + 0.5),
            math.floor((rgb[3] or 0) * factor + 0.5)
        }
    end

    local function find_region(project, region_number)
        if not project then return nil, nil end

        local _, marker_count, region_count =
            reaper.CountProjectMarkers(project)

        for index = 0, marker_count + region_count - 1 do
            local _, is_region, start_pos, end_pos, _, number =
                reaper.EnumProjectMarkers2(project, index)

            if is_region and number == region_number then
                return start_pos, end_pos
            end
        end

        return nil, nil
    end

    local function pattern_has_content(track, region)
        local project = reaper.EnumProjects(track - 1, "")
        if not project then return false end

        local region_start, region_end = find_region(project, region)
        if not region_start or not region_end then return false end

        local item_count = reaper.CountMediaItems(project)

        for index = 0, item_count - 1 do
            local item = reaper.GetMediaItem(project, index)
            local item_start =
                reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_length =
                reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = item_start + item_length

            -- Elke echte overlap met de region telt als inhoud.
            if item_end > region_start and item_start < region_end then
                return true
            end
        end

        return false
    end

    local function draw_pattern_track(row, track, color)
        local group = "pattern_track_" .. track
        local state = api.get_screen_state(1)
        local saved_note = state.radio[group]
        local selected_col = saved_note and (saved_note % 10) or 1

        local visual_state = nil
        if api.pattern
        and type(api.pattern.get_visual_state) == "function" then
            visual_state = api.pattern.get_visual_state(track, selected_col)
        end

        local active_color = C.WHITE
        if visual_state == "queued" then
            active_color = C.LIGHT_BLUE
        end

        local empty_color = dim_rgb(color, EMPTY_BRIGHTNESS)

        local function handle_press(pad)
            local region = pad.col

            -- Update pattern/scene feedback only. Screen 1 never
            -- changes screen 0 or the active REAPER track.
            if api.set_scene_pattern then
                api.set_scene_pattern(track, region)
            end

            -- Queue/selecteer daarna het echte pattern.
            api.pattern.select(
                track,
                region
            )

            -- Mirror only the region when Screen 1 edits the same
            -- instrument that is currently active in Main.
            local main_track = tonumber(
                reaper.GetExtState("GJS_X", "ActiveTrack")
            ) or 1

            if main_track == track and api.set_main_region then
                api.set_main_region(region)
            end
        end

        -- Los tekenen in plaats van drawstrip: zo kan iedere niet-actieve
        -- pad zijn eigen donker/licht achtergrond krijgen terwijl de
        -- geselecteerde pad gewoon wit of lichtblauw blijft.
        for col = 1, 8 do
            local background = pattern_has_content(track, col)
                and color
                or empty_color

            api.drawpad(
                row,
                col,
                color,
                api.MODE_RADIO,
                {
                    group = group,
                    active = selected_col == col,
                    active_color = active_color,
                    background_rgb = background,
                    on_press = handle_press
                }
            )
        end
    end

    draw_pattern_track(8, 1, C.RED)
    draw_pattern_track(7, 2, C.ORANGE)
    draw_pattern_track(6, 3, C.GREEN)
    draw_pattern_track(5, 4, C.YELLOW)
    draw_pattern_track(4, 5, C.MAGENTA)
    draw_pattern_track(3, 6, C.PURPLE)
    draw_pattern_track(2, 7, C.PINK)
    draw_pattern_track(1, 8, C.BLUE)
end
