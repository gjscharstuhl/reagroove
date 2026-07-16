-- ============================================================
-- Screen 7: temporary color test
-- ============================================================

return function(api)
    local C = api.COLOR
    local colors = {
        C.RED,
        C.ORANGE,
        C.YELLOW,
        C.GREEN,
        C.LIGHT_BLUE,
        C.BLUE,
        C.LIGHT_PURPLE,
        C.PURPLE
    }

    for row = 1, 8 do
        local color_index = ((row + 7 - 2) % 8) + 1

        api.drawstrip(
            row, 1, 8,
            colors[color_index],
            api.MODE_HIGHLIGHT,
            { active_color = api.SELECT_COLOR }
        )
    end
end
