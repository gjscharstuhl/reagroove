-- gjs - scene_api.lua

local M = {}

------------------------------------------------------------
-- Live scene
------------------------------------------------------------

local scene = {

    current = nil,
    next = nil,

    patternlist = {
        1,1,1,1,
        1,1,1,1
    }

}

------------------------------------------------------------
-- Opgeslagen scenes
------------------------------------------------------------

local scenelist = {}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function copy(tbl)

    local result = {}

    for k,v in pairs(tbl) do

        if type(v) == "table" then
            result[k] = copy(v)
        else
            result[k] = v
        end

    end

    return result

end

------------------------------------------------------------
-- API
------------------------------------------------------------



function M.GetSceneList()
    return scenelist
end

function M.GetScene(scene_nr)
    return scenelist[scene_nr]
end

function M.SaveScene(scene_nr)

    scene_nr = tonumber(scene_nr)

    if not scene_nr then
        return false
    end

    scenelist[scene_nr] = copy(scene)

    return true

end

function M.LoadScene(scene_nr)

    scene_nr = tonumber(scene_nr)

    if not scene_nr then
        return false
    end

    if not scenelist[scene_nr] then
        return false
    end

    scene = copy(scenelist[scene_nr])

    return true

end

function M.Clear()

    scene = {

        current = nil,
        next = nil,

        patternlist = {
            1,1,1,1,
            1,1,1,1
        }

    }

    scenelist = {}

end

function M.set_pattern(track, region)

    track = tonumber(track)
    region = tonumber(region)

    if not track or not region then
        return false
    end

    if track < 1 or track > #scene.patternlist then
        return false
    end

    scene.patternlist[track] = region

    return true

end

function M.get_pattern(track)

    track = tonumber(track)

    if not track then
        return nil
    end

    return scene.patternlist[track]

end

return M
