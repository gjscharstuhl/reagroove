-- ============================================================
-- Screen 0: main screen
-- ============================================================

return function(api)
    local C = api.COLOR

    local function get_selected_track_and_region()
        local state = api.get_screen_state(0)

        local track_note =
            state.radio["tracks"] or 11

        local region_note =
            state.radio["regions"] or 61

        local track = track_note - 10
        local region = region_note - 60

        return track, region
    end

    local function select_current_pattern()
        if not api.pattern
        or type(api.pattern.select) ~= "function" then
            return
        end

        local track, region =
            get_selected_track_and_region()

        api.pattern.select(track, region)
    end

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

    -- Regions 1 t/m 8
    api.drawstrip(
        6, 1, 8,
        C.LIGHT_BLUE,
        api.MODE_RADIO,
        {
            group = "regions",
            selected_col = 1,
            active_color = api.SELECT_COLOR,

            on_press = function()
                select_current_pattern()
            end
        }
    )

    -- Play
    api.drawpad(
        4,
        1,
        C.GREEN,
        api.MODE_HIGHLIGHT,
        {
            active_color = api.SELECT_COLOR,

            on_press = function()
                if api.transport then
                    api.transport.play()
                end
            end
        }
    )

    -- Record
    api.drawpad(
        4,
        2,
        C.YELLOW,
        api.MODE_HIGHLIGHT,
        {
            active_color = api.SELECT_COLOR,

            on_press = function()
                if api.transport then
                    api.transport.record()
                end
            end,

            on_release = function()
                if api.transport then
                    api.transport.invalidate_record_led()
                end
            end
        }
    )

    -- Stop
    api.drawpad(
        4,
        3,
        C.GREY,
        api.MODE_HIGHLIGHT,
        {
            active_color = api.SELECT_COLOR,

            on_press = function()
                if api.transport then
                    api.transport.stop()
                end
            end
        }
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

    api.drawpad(
        3,
        5,
        C.PURPLE,
        api.MODE_HIGHLIGHT
    )

    api.drawpad(
        3,
        6,
        C.LIGHT_PURPLE,
        api.MODE_HIGHLIGHT
    )

    api.drawpad(
        3,
        7,
        C.LIGHT_PURPLE,
        api.MODE_HIGHLIGHT
    )

    api.drawpad(
        3,
        8,
        C.LIGHT_BLUE,
        api.MODE_HIGHLIGHT
    )

    api.drawstrip(
        2, 1, 8,
        C.DARK_YELLOW,
        api.MODE_TOGGLE,
        {
            active_color = api.SELECT_COLOR
        }
    )

    -- Tracks 1 t/m 8
    api.drawstrip(
        1, 1, 8,
        C.ORANGE,
        api.MODE_RADIO,
        {
            group = "tracks",
            selected_col = 1,
            active_color = api.SELECT_COLOR,

            on_press = function()
                select_current_pattern()
            end
        }
    )
end
