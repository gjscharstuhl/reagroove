local RGB_COLOR = {
    RED     = {127,   0,   0},
    ORANGE  = {127,  35,   0},
    GREEN   = {  0, 127,   0},
    YELLOW  = {127, 100,   0},
    MAGENTA = {127,   0,  70},
    PURPLE  = { 55,   0, 127},
    PINK    = {127,  20,  90},
    BLUE    = {  0,  35, 127}
}

local BALANCE_RGB = {
    RGB_COLOR.RED,
    RGB_COLOR.ORANGE,
    RGB_COLOR.GREEN,
    RGB_COLOR.YELLOW,
    RGB_COLOR.MAGENTA,
    RGB_COLOR.PURPLE,
    RGB_COLOR.PINK,
    RGB_COLOR.BLUE
}

local function drawscreen3(api)
    for row = 1, 8 do
        api.draw_horizontal_fader(
            row,
            BALANCE_RGB[row],
            {
                group = "balance_fader_" .. row
            }
        )
    end

    -- De acht rijen gespreid opnieuw tekenen,
    -- zodat gmem-opdrachten elkaar niet overschrijven.
    local index = 1
    local last_time = reaper.time_precise()

    local function redraw_next()
        local now = reaper.time_precise()

        if now - last_time < 0.01 then
            reaper.defer(redraw_next)
            return
        end

        api.render_horizontal_fader(
            "balance_fader_" .. index
        )

        index = index + 1
        last_time = now

        if index <= 8 then
            reaper.defer(redraw_next)
        end
    end

    redraw_next()
end

return drawscreen3
