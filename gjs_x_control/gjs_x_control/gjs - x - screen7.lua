local function drawscreen7(api)
    local C = api.COLOR
    local H = api.MODE_HIGHLIGHT

    -- Magenta
    api.drawpad(7,4,C.MAGENTA,H)
    api.drawpad(7,5,C.MAGENTA,H)

    api.drawpad(6,4,C.MAGENTA,H)
    api.drawpad(6,5,C.MAGENTA,H)

    -- Wit / Geel / Paars
    api.drawpad(5,2,C.WHITE,H)
    api.drawpad(5,3,C.YELLOW,H)
    api.drawpad(5,4,C.MAGENTA,H)
    api.drawpad(5,5,C.PURPLE,H)
    api.drawpad(5,6,C.YELLOW,H)
    api.drawpad(5,7,C.WHITE,H)

    -- Groen / Blauw / Cyan
    api.drawpad(4,2,C.GREEN,H)
    api.drawpad(4,3,C.BLUE,H)
    api.drawpad(4,4,C.LIGHT_BLUE,H)
    api.drawpad(4,5,C.LIGHT_BLUE,H)
    api.drawpad(4,6,C.BLUE,H)
    api.drawpad(4,7,C.GREEN,H)

    -- Oranje / Geel
    api.drawpad(3,2,C.ORANGE,H)
    api.drawpad(3,4,C.YELLOW,H)
    api.drawpad(3,5,C.YELLOW,H)
    api.drawpad(3,7,C.ORANGE,H)

    -- Lichtpaars / Oranje
    api.drawpad(2,2,C.LIGHT_PURPLE,H)
    api.drawpad(2,4,C.ORANGE,H)
    api.drawpad(2,5,C.ORANGE,H)
    api.drawpad(2,7,C.LIGHT_PURPLE,H)

    -- Rood
    api.drawpad(1,4,C.RED,H)
    api.drawpad(1,5,C.RED,H)
end

return drawscreen7
