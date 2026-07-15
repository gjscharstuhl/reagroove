-- ============================================================
-- Screen 0: main screen
-- ============================================================

return function(api)
    local C = api.COLOR

    api.drawblock(
        8, 1,
        7, 8,
        C.GREY,
        api.MODE_RADIO,
        {
            group = "sequencer_patterns",
            selected_row = 8,
            selected_col = 1,
            active_color = api.SELECT_COLOR
        }
    )

    api.drawstrip(
        6, 1, 8,
        C.LIGHT_BLUE,
        api.MODE_RADIO,
        {
            group = "regions",
            selected_col = 1,
            active_color = api.SELECT_COLOR
        }
    )

    api.drawpad(
        4, 1,
        C.GREEN,
        api.MODE_HIGHLIGHT,
        { active_color = api.SELECT_COLOR }
    )

    api.drawpad(
        4, 2,
        C.YELLOW,
        api.MODE_HIGHLIGHT,
        { active_color = api.SELECT_COLOR }
    )

    api.drawpad(
        4, 3,
        C.GREY,
        api.MODE_HIGHLIGHT,
        { active_color = api.SELECT_COLOR }
    )

    api.drawstrip(
        4, 5, 8,
        C.BLUE,
        api.MODE_RADIO,
        {
            group = "page_selector",
            selected_col = 5,
            active_color = api.SELECT_COLOR
        }
    )

    api.drawpad(3, 5, C.PURPLE, api.MODE_HIGHLIGHT)
    api.drawpad(3, 6, C.LIGHT_PURPLE, api.MODE_HIGHLIGHT)
    api.drawpad(3, 7, C.LIGHT_PURPLE, api.MODE_HIGHLIGHT)
    api.drawpad(3, 8, C.LIGHT_BLUE, api.MODE_HIGHLIGHT)

    api.drawstrip(
        2, 1, 8,
        C.DARK_YELLOW,
        api.MODE_TOGGLE,
        { active_color = api.SELECT_COLOR }
    )

    api.drawstrip(
        1, 1, 8,
        C.ORANGE,
        api.MODE_RADIO,
        {
            group = "tracks",
            selected_col = 1,
            active_color = api.SELECT_COLOR
        }
    )
end
