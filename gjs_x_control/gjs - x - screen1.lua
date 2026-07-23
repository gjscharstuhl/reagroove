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

        api.drawstrip(
            row,
            1,
            8,
            color,
            api.MODE_RADIO,
            {
                group = group,
                selected_col = selected_col,
                active_color = active_color,

                on_press = function(pad)
                    local region = pad.col

                    -- Bewaar de gekozen track en region voor screen 0.
                    -- Trackselector: onderste rij.
                    -- Regionselector: derde rij van boven (row 6).
                    api.set_track_and_region(
                        track,
                        region
                    )

                    -- Queue/selecteer daarna het echte pattern.
                    api.pattern.select(
                        track,
                        region
                    )
                end
            }
        )
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
