local scene_api = include("gjs - scene_api.lua")

local operation = 1
local active_scene = 1

local API

------------------------------------------------------------
-- Scene colours
------------------------------------------------------------


local SCENE_EMPTY  = { 10, 3, 0 }
local SCENE_SAVED  = { 127, 35, 0 }
local SCENE_ACTIVE = { 127, 127, 127 }
------------------------------------------------------------
-- Scene operations
------------------------------------------------------------

local function loadscene(scene_nr)

    local scene = scene_api.GetScene(scene_nr)

    if not API then
        reaper.ShowConsoleMsg("geen API\n")
        return
    end

    if not scene then
        API.dump(
            "Scene " ..
            tostring(scene_nr) ..
            " bestaat niet.",
            "Scene"
        )
        return
    end

    API.dump(
        scene,
        "Scene " .. tostring(scene_nr)
    )

    local patternlist =
        scene.patternlist or {}

    API.pattern.queue_scene(
        patternlist
    )
end

local function savescene(scene_nr)
    scene_api.SaveScene(scene_nr)
end

local function copytoplaylist(scene_nr)
    reaper.ShowConsoleMsg(
        "hello from copy " ..
        tostring(scene_nr) ..
        "\n"
    )
end

local operations = {
    [1] = loadscene,
    [2] = savescene,
    [3] = copytoplaylist,
}

local function DoOperation(operation_nr)

    local operation_function =
        operations[operation_nr]

    if operation_function then
        operation_function(active_scene)
    end
end

------------------------------------------------------------
-- Pad/scene conversion
------------------------------------------------------------

local function pad_to_scene(row, col)
    return ((3 - row) * 8) + col
end

------------------------------------------------------------
-- Screen
------------------------------------------------------------

local function drawscreen4(api)

    API = api

    local C = api.COLOR

    --------------------------------------------------------
    -- Bovenste twee grijze rijen
    --------------------------------------------------------

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

    --------------------------------------------------------
    -- Region selection
    --------------------------------------------------------

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

    --------------------------------------------------------
    -- Playlist
    --------------------------------------------------------

    api.drawblock(
        5, 1,
        4, 8,
        C.GREEN,
        api.MODE_TOGGLE,
        {
            active_color = C.WHITE
        }
    )

    --------------------------------------------------------
    -- Scene selection: scenes 1 t/m 16
    --------------------------------------------------------

    local active_row
    local active_col

    if active_scene <= 8 then
        active_row = 3
        active_col = active_scene
    else
        active_row = 2
        active_col = active_scene - 8
    end

	local function scene_background_rgb(row, col)

		local scene_nr =
			pad_to_scene(row, col)

		if scene_nr == active_scene then
			return SCENE_ACTIVE
		end

		if scene_api.GetScene(scene_nr) then
			return SCENE_SAVED
		end

		return SCENE_EMPTY
	end

	api.drawblock(
		3, 1,
		2, 8,
		C.OFF,
		api.MODE_RADIO,
		{
			group = "scene_selection",

			selected_row = active_row,
			selected_col = active_col,

			active_color = C.WHITE,
			background_rgb = scene_background_rgb,

			on_release = function(pad)
				active_scene =
					pad_to_scene(
						pad.row,
						pad.col
					)

				api.redraw()
			end
		}
	)

    --------------------------------------------------------
    -- Operations
    --------------------------------------------------------

    api.drawstrip(
        1, 1, 8,
        C.ORANGE,
        api.MODE_RADIO,
        {
            group = "scenes_operations",
            selected_col = operation,
            active_color = C.WHITE,

            on_press = function(pad)

                operation = pad.col

                DoOperation(operation)

                -- Na opslaan opnieuw tekenen zodat de scene
                -- direct fel oranje wordt.
                if operation == 2 then
                    reaper.defer(function()
                        api.redraw()
                    end)
                end
            end
        }
    )
end

return drawscreen4
