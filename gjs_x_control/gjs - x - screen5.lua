local function drawscreen5(api)
    local C = api.COLOR

    -- Linksboven: blauwe save-slots
    api.drawblock(
        8, 1,
        5, 4,
        C.BLUE,
        api.MODE_RADIO,
        {
            group = "save_slots_blue",
            selected_row = 8,
            selected_col = 1,
            active_color = C.WHITE
        }
    )

    -- Rechtsboven: oranje save-slots
    api.drawblock(
        8, 5,
        5, 8,
        C.ORANGE,
        api.MODE_RADIO,
        {
            group = "save_slots_orange",
            selected_row = 8,
            selected_col = 5,
            active_color = C.WHITE
        }
    )

    -- Onderste functietoetsen
    api.drawpad(2, 5, C.YELLOW, api.MODE_HIGHLIGHT)
    api.drawpad(2, 6, C.RED,    api.MODE_HIGHLIGHT)
    api.drawpad(2, 7, C.GREEN,  api.MODE_HIGHLIGHT)
    api.drawpad(2, 8, C.BLUE,   api.MODE_HIGHLIGHT)
end

return drawscreen5
