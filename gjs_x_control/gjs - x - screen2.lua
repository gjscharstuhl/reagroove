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

local FADER_RGB = {
    RGB_COLOR.RED,
    RGB_COLOR.ORANGE,
    RGB_COLOR.GREEN,
    RGB_COLOR.YELLOW,
    RGB_COLOR.MAGENTA,
    RGB_COLOR.PURPLE,
    RGB_COLOR.PINK,
    RGB_COLOR.BLUE
}

local function drawscreen2(api)
    for col = 1, 8 do
        api.drawfader(
            col,
            FADER_RGB[col],
            {
                group = "mixer_fader_" .. col,
                default_row = 1,
                default_step = 4
            }
        )
    end

    local groups = {
        "mixer_fader_1",
        "mixer_fader_2",
        "mixer_fader_3",
        "mixer_fader_4",
        "mixer_fader_5",
        "mixer_fader_6",
        "mixer_fader_7",
        "mixer_fader_8"
    }

    local index = 1
    local last_time = reaper.time_precise()

    local function redraw_next_fader()
        local now = reaper.time_precise()

        if now - last_time < 0.005 then
            reaper.defer(redraw_next_fader)
            return
        end

        api.render_fader(groups[index])

        index = index + 1
        last_time = now

        if index <= #groups then
            reaper.defer(redraw_next_fader)
        end
    end

    redraw_next_fader()
end

return drawscreen2
