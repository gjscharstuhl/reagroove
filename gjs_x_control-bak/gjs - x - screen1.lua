-- ============================================================
-- Screen 1: pattern launcher
-- Each row is one track/subproject.
-- Each column is one region.
-- ============================================================

return function(api)
    local C = api.COLOR

    local function draw_pattern_track(row, track, color)
        api.drawstrip(
            row, 1, 8,
            color,
            api.MODE_RADIO,
            {
                group = "pattern_track_" .. track,
                selected_col = 1,
                active_color = C.WHITE,

                on_press = function(pad)
                    api.set_screen0_track_and_region(
                        track,
                        pad.col
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
