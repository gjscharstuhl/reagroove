-- gjs - scene_api.lua

local M = {}

------------------------------------------------------------
-- Live scene
------------------------------------------------------------

local scene = {

    active_track = 1,

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

local function get_current_active_track()

    local active_track = tonumber(
        reaper.GetExtState("GJS_X", "ActiveTrack")
    )

    if not active_track then
        active_track = tonumber(
            reaper.GetExtState("GJS_MULTI", "ActiveTrack")
        )
    end

    if not active_track
    or active_track < 1
    or active_track > 8 then
        return 1
    end

    return math.floor(active_track)

end

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

    local saved_scene = copy(scene)

    -- Save the track that is active at the exact moment
    -- this scene is stored. No fixed track number is used.
    saved_scene.active_track = get_current_active_track()

    scenelist[scene_nr] = saved_scene

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

        active_track = 1,

        patternlist = {
            1,1,1,1,
            1,1,1,1
        }

    }

    scenelist = {}

end

function M.get_active_track()

    local active_track = tonumber(scene.active_track)

    -- Compatibility with older scenes that do not yet contain
    -- an active_track value.
    if not active_track or active_track < 1 or active_track > 8 then
        return get_current_active_track()
    end

    return math.floor(active_track)

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
