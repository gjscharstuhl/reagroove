local function drawscreen4(api)
    local C = api.COLOR

    -- Bovenste twee grijze rijen:
    -- samen één radiogroep van 16 pads.
    api.drawblock(
        8, 1,
        7, 8,
        C.GREY,
        api.MODE_RADIO,
        {
            group = "scenes_patterns",
            selected_row = 8,
            selected_col = 1,
            active_color = C.WHITE
        }
    )

    -- Lichtblauwe selectorrij.
    api.drawstrip(
        6, 1, 8,
        C.LIGHT_BLUE,
        api.MODE_RADIO,
        {
            group = "scenes_regions",
            selected_col = 1,
            active_color = C.WHITE
        }
    )

    -- Groen toggle-block: rijen 3 t/m 5.
    api.drawblock(
        5, 1,
        3, 8,
        C.GREEN,
        api.MODE_TOGGLE,
        {
            active_color = C.WHITE
        }
    )

    -- Geel toggle-block: onderste twee rijen.
    api.drawblock(
        2, 1,
        1, 8,
        C.YELLOW,
        api.MODE_TOGGLE,
        {
            active_color = C.WHITE
        }
    )
end

return drawscreen4
