local scene_api = include("gjs - scene_api.lua")

local operation=1
local active_scene=1

local API


local function loadscene(scene_nr)

    local scene = scene_api.GetScene(scene_nr)
	if not API then
		reaper.ShowConsoleMsg("geen API")
		return
	end
    if not scene then
        API.dump(
            "Scene " .. tostring(scene_nr) .. " bestaat niet.",
            "Scene"
        )
        return
    end

    API.dump(scene, "Scene " .. tostring(scene_nr))
    
    local patterns = scene.patternlist or {}


    for track = 1, 8 do
        local region = patterns[track]

        if region then
            API.set_track_and_region(
                track,
                region
            )

            API.pattern.select(
                track,
                region
            )
            reaper.ShowConsoleMsg("load track,region "..tostring(track)..","..tostring(region))
        end
    end


    API.redraw()

end


local function savescene(scene_nr)
    scene_api.SaveScene(scene_nr)
end
	


local function copytoplaylist(scene)
	reaper.ShowConsoleMsg("hello from copy"..tostring(scene))
end


local operations = {
    [1] = loadscene,
    [2] = savescene,
    [3] = copytoplaylist,
}

local function DoOperation(operation)
    local f = operations[operation]
    if f then
        f(active_scene)
    end
end


local function DoOperation(operation)
    local f = operations[operation]
    if f then
        f(active_scene)
    end
end


local function drawscreen4(api)
	API=api
    local C = api.COLOR
	
    -- Bovenste twee grijze rijen: sequenser zoals in screen 0
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

    -- Lichtblauwe selectorrij. region selection (of iets anders)
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

    -- Groen toggle-block: playlist
    api.drawblock(
        5, 1,
        4, 8,
        C.GREEN,
        api.MODE_TOGGLE,
        {
            active_color = C.WHITE
        }
    )

    -- Geel toggle-block: scene selectie
    api.drawblock(
        3, 1,
        2, 8,
        C.YELLOW,
        api.MODE_RADIO,
        {
            selected_row = 3,
            selected_col = 1,
            active_color = C.WHITE,
            on_press = function(pad)
                
                     active_scene=pad.col
                     reaper.ShowConsoleMsg("active scene ="..tostring(active_scene))
            
            end
        }
    )
    
        -- Geel toggle-block: scene selectie
   api.drawstrip(
        1, 1, 8,
        C.ORANGE,
        api.MODE_RADIO,
        {
            group = "scenes_operations",
            selected_row = 8,
            selected_col = 1,
            active_color = C.WHITE,
             on_press = function(pad)
                
                     DoOperation(pad.col,active_scene)
            
            end
        }
    )
end

return drawscreen4
