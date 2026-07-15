-- ============================================================
-- Screen 2: mixer faders
-- Eight vertical faders with four brightness refinement steps.
-- ============================================================

return function(api)
    local C = api.COLOR

    local fader_colors = {
        [1] = { full = C.RED,          steps = { 7, 6, 4, C.RED } },
        [2] = { full = C.ORANGE,       steps = { 11, 10, 8, C.ORANGE } },
        [3] = { full = C.GREEN,        steps = { 23, 22, 20, C.GREEN } },
        [4] = { full = C.YELLOW,       steps = { 15, 14, 12, C.YELLOW } },
        [5] = { full = C.MAGENTA,      steps = { 55, 54, 51, C.MAGENTA } },
        [6] = { full = C.PURPLE,       steps = { 71, 70, 68, C.PURPLE } },
        [7] = { full = C.PINK,         steps = { 55, 54, 51, C.PINK } },
        [8] = { full = C.BLUE,         steps = { 47, 46, 44, C.BLUE } }
    }

    for col = 1, 8 do
        local colors = fader_colors[col]

        api.drawfader(
            col,
            colors.full,
            colors.steps,
            {
                group = "mixer_fader_" .. col,
                default_row = 1,
                default_step = 4
            }
        )
    end
end
