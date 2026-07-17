-- ============================================================
-- Screen 1: pattern launcher
-- Each row is one track/subproject.
-- Each column is one region.
-- ============================================================

return function(api)
    local C = api.COLOR

    local function draw_pattern_track(row, track, color)
        api.drawstrip(
            row,
            1,
            8,
            color,
            api.MODE_RADIO,
            {
                group = "pattern_track_" .. track,

                -- Standaard eerste region geselecteerd.
                selected_col = 1,

                -- Geselecteerd pattern wordt wit.
                active_color = C.WHITE,

                on_press = function(pad)
                    local region = pad.col

                    if not api.pattern then
                        reaper.ShowConsoleMsg(
                            "Screen 1: api.pattern ontbreekt\n"
                        )
                        return
                    end

                    local ok = api.pattern.select(
                        track,
                        region
                    )

                    if not ok then
                        reaper.ShowConsoleMsg(
                            string.format(
                                "Screen 1: patternselectie mislukt: " ..
                                "track=%d region=%d\n",
                                track,
                                region
                            )
                        )
                    end
                end
            }
        )
    end

    -- Onderste rij = track/projecttab 1.
    -- Bovenste rij = track/projecttab 8.
    draw_pattern_track(8, 1, C.RED)
    draw_pattern_track(7, 2, C.ORANGE)
    draw_pattern_track(6, 3, C.GREEN)
    draw_pattern_track(5, 4, C.YELLOW)
    draw_pattern_track(4, 5, C.MAGENTA)
    draw_pattern_track(3, 6, C.PURPLE)
    draw_pattern_track(2, 7, C.PINK)
    draw_pattern_track(1, 8, C.BLUE)
end
