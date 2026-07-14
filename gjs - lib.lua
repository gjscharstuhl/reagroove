local M = {}

------------------------------------------------------------
-- Pattern Launcher configuratie
------------------------------------------------------------

local EXT_SECTION = "PatternLauncher"
local EXT_KEY = "SceneState"
local TRACK_COUNT = 8


------------------------------------------------------------
-- Bestaande trackfuncties
------------------------------------------------------------

local function get_regions_folder_track_number(folder)
    if not folder then
        return nil
    end

    folder = folder:lower()

    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        local _, name = reaper.GetTrackName(tr)

        if name:lower() == folder then
            return math.floor(
                reaper.GetMediaTrackInfo_Value(
                    tr,
                    "IP_TRACKNUMBER"
                )
            )
        end
    end

    return nil
end


local function get_selected_region_track(folder)
    local folder_nr =
        get_regions_folder_track_number(folder)

    if not folder_nr then
        return nil
    end

    local tr_idx = folder_nr

    while tr_idx < reaper.CountTracks(0) do
        local tr = reaper.GetTrack(0, tr_idx)

        if not tr then
            break
        end

        if reaper.IsTrackSelected(tr) then
            return tr
        end

        local depth =
            reaper.GetMediaTrackInfo_Value(
                tr,
                "I_FOLDERDEPTH"
            )

        if depth < 0 then
            break
        end

        tr_idx = tr_idx + 1
    end

    return nil
end


local function cleararm(proj)
    local _, _, sectionID, cmdID =
        reaper.get_action_context()

    for i = 0, reaper.CountTracks(proj) - 1 do
        local tr = reaper.GetTrack(proj, i)

        if tr then
            reaper.SetTrackSelected(tr, false)

            reaper.SetMediaTrackInfo_Value(
                tr,
                "I_RECARM",
                0
            )

            reaper.SetMediaTrackInfo_Value(
                tr,
                "I_AUTOMODE",
                0
            )

            reaper.SetToggleCommandState(
                sectionID,
                cmdID,
                0
            )
        end
    end
end


function M.arm(nr, page)
    nr = tonumber(nr)
    page = tonumber(page)

    if not nr or not page then
        return false
    end

    local _, _, sectionID, cmdID =
        reaper.get_action_context()

    -- Tabs 2 t/m 9 = tracks 1 t/m 8
    for tab = 2, 9 do
        local proj = reaper.EnumProjects(tab - 1)

        if proj then
            local mytracknr = tab - 1

            cleararm(proj)

            -- Eerste track in het subproject
            local track = reaper.GetTrack(proj, 0)

            if track and mytracknr == nr then
                if page == 1 then
                    reaper.SetTrackSelected(
                        track,
                        true
                    )

                    reaper.SetMediaTrackInfo_Value(
                        track,
                        "I_RECARM",
                        1
                    )

                elseif page == 2 then
                    reaper.SetTrackSelected(
                        track,
                        true
                    )

                    reaper.SetMediaTrackInfo_Value(
                        track,
                        "I_AUTOMODE",
                        4
                    )

                    reaper.SetToggleCommandState(
                        sectionID,
                        cmdID,
                        1
                    )

                    reaper.SetMediaTrackInfo_Value(
                        track,
                        "I_RECARM",
                        1
                    )
                end
            end
        end
    end

    return true
end


function M.target(folder)
    local region_track =
        get_selected_region_track(folder)

    local tracknr

    if region_track then
        tracknr =
            reaper.GetMediaTrackInfo_Value(
                region_track,
                "IP_TRACKNUMBER"
            )
    end

    local regionfoldernr =
        get_regions_folder_track_number(folder)

    if tracknr == nil or regionfoldernr == nil then
        return nil
    end

    local target_region_number =
        tracknr - regionfoldernr

    return target_region_number
end


function M.get_current_project_tab_number()
    local current_proj =
        reaper.EnumProjects(-1)

    for i = 0, 99 do
        local proj = reaper.EnumProjects(i)

        if not proj then
            break
        end

        if proj == current_proj then
            -- Tabnummer is 1-based
            return i + 1
        end
    end

    return nil
end


local function getTrackByName(name)
    if not name then
        return nil
    end

    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        local _, trName = reaper.GetTrackName(tr)

        if trName == name then
            return tr
        end
    end

    return nil
end


function M.GetTrackByName(name)
    return getTrackByName(name)
end


function M.SelectTrackInFolder(folderName, tracknr)
    tracknr = tonumber(tracknr)

    if not folderName or not tracknr then
        return nil
    end

    local folderTrack
    local folderIndex

    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        local _, name = reaper.GetTrackName(tr)

        if name == folderName then
            folderTrack = tr
            folderIndex = i
            break
        end
    end

    if not folderTrack then
        return nil
    end

    local folderDepth =
        reaper.GetTrackDepth(folderTrack)

    local found = 0
    local targetTrack = nil

    for i = folderIndex + 1,
        reaper.CountTracks(0) - 1
    do
        local tr = reaper.GetTrack(0, i)
        local depth = reaper.GetTrackDepth(tr)

        if depth <= folderDepth then
            break
        end

        -- Alleen deselecteren binnen deze folder
        reaper.SetTrackSelected(tr, false)

        -- Alleen directe children tellen
        if depth == folderDepth + 1 then
            found = found + 1

            if found == tracknr then
                targetTrack = tr
            end
        end
    end

    if targetTrack then
        reaper.SetTrackSelected(
            targetTrack,
            true
        )
    end

    return targetTrack
end


------------------------------------------------------------
-- SceneManager: interne hulpfuncties
------------------------------------------------------------

local function is_positive_integer(value)
    return type(value) == "number"
        and value >= 1
        and value == math.floor(value)
end


local function copyScene(scene)
    local result = {}

    for trackNumber = 1, TRACK_COUNT do
        result[trackNumber] =
            scene[trackNumber]
    end

    return result
end


local function createDefaultScene(sceneNumber)
    local scene = {}

    -- Standaard verwijst iedere track naar hetzelfde nummer
    -- als de scene.
    --
    -- Scene 3 wordt dus:
    -- {3, 3, 3, 3, 3, 3, 3, 3}
    for trackNumber = 1, TRACK_COUNT do
        scene[trackNumber] = sceneNumber
    end

    return scene
end


local function createDefaultState()
    return {
        currentScene = 1,
        nextScene = 1,
        scenes = {}
    }
end


local function serializeState(state)
    local parts = {
        "currentScene=" ..
            tostring(state.currentScene or 1),

        "nextScene=" ..
            tostring(
                state.nextScene
                or state.currentScene
                or 1
            )
    }

    local sceneNumbers = {}

    for sceneNumber in pairs(state.scenes) do
        sceneNumbers[#sceneNumbers + 1] =
            sceneNumber
    end

    table.sort(sceneNumbers)

    for _, sceneNumber in ipairs(sceneNumbers) do
        local scene = state.scenes[sceneNumber]
        local trackValues = {}

        for trackNumber = 1, TRACK_COUNT do
            local value = scene[trackNumber]

            if value == nil then
                value = sceneNumber
            end

            trackValues[#trackValues + 1] =
                tostring(value)
        end

        parts[#parts + 1] =
            "scene" ..
            tostring(sceneNumber) ..
            "=" ..
            table.concat(trackValues, ",")
    end

    return table.concat(parts, ";")
end


local function deserializeState(serialized)
    local state = createDefaultState()

    if not serialized or serialized == "" then
        return state
    end

    for key, value
        in serialized:gmatch("([^=;]+)=([^;]+)")
    do
        if key == "currentScene" then
            state.currentScene =
                tonumber(value) or 1

        elseif key == "nextScene" then
            state.nextScene =
                tonumber(value)
                or state.currentScene

        else
            local sceneNumber =
                tonumber(
                    key:match("^scene(%d+)$")
                )

            if sceneNumber then
                local scene =
                    createDefaultScene(sceneNumber)

                local trackNumber = 1

                for trackValue
                    in value:gmatch("[^,]+")
                do
                    if trackNumber > TRACK_COUNT then
                        break
                    end

                    scene[trackNumber] =
                        tonumber(trackValue)
                        or sceneNumber

                    trackNumber =
                        trackNumber + 1
                end

                state.scenes[sceneNumber] =
                    scene
            end
        end
    end

    return state
end


local function loadState()
    local serialized =
        reaper.GetExtState(
            EXT_SECTION,
            EXT_KEY
        )

    return deserializeState(serialized)
end


local function saveState(state)
    local serialized =
        serializeState(state)

    reaper.SetExtState(
        EXT_SECTION,
        EXT_KEY,
        serialized,
        true
    )

    return serialized
end


local function ensureScene(state, sceneNumber)
    if not state.scenes[sceneNumber] then
        state.scenes[sceneNumber] =
            createDefaultScene(sceneNumber)
    end

    return state.scenes[sceneNumber]
end


------------------------------------------------------------
-- SceneManager: publieke API
------------------------------------------------------------

function M.getScene(sceneNumber)
    sceneNumber = tonumber(sceneNumber)

    if not is_positive_integer(sceneNumber) then
        return nil, "Ongeldig scenenummer"
    end

    local state = loadState()
    local scene =
        ensureScene(state, sceneNumber)

    -- De automatisch aangemaakte scene meteen globaal
    -- opslaan.
    saveState(state)

    return copyScene(scene)
end


function M.setScene(sceneNumber, sceneData)
    sceneNumber = tonumber(sceneNumber)

    if not is_positive_integer(sceneNumber) then
        return false, "Ongeldig scenenummer"
    end

    if type(sceneData) ~= "table" then
        return false,
            "sceneData moet een Lua-table zijn"
    end

    local state = loadState()
    local scene =
        createDefaultScene(sceneNumber)

    for trackNumber = 1, TRACK_COUNT do
        local patternNumber =
            tonumber(sceneData[trackNumber])

        if patternNumber ~= nil then
            if not is_positive_integer(
                patternNumber
            ) then
                return false,
                    "Ongeldig patternnummer voor track "
                    .. tostring(trackNumber)
            end

            scene[trackNumber] =
                patternNumber
        end
    end

    state.scenes[sceneNumber] = scene

    saveState(state)

    return true
end


function M.getTrackScene(
    sceneNumber,
    trackNumber
)
    sceneNumber = tonumber(sceneNumber)
    trackNumber = tonumber(trackNumber)

    if not is_positive_integer(sceneNumber) then
        return nil, "Ongeldig scenenummer"
    end

    if not is_positive_integer(trackNumber)
        or trackNumber > TRACK_COUNT
    then
        return nil, "Ongeldig tracknummer"
    end

    local state = loadState()
    local scene =
        ensureScene(state, sceneNumber)

    saveState(state)

    return scene[trackNumber]
end


function M.setTrackScene(
    sceneNumber,
    trackNumber,
    patternNumber
)
    sceneNumber = tonumber(sceneNumber)
    trackNumber = tonumber(trackNumber)
    patternNumber = tonumber(patternNumber)

    if not is_positive_integer(sceneNumber) then
        return false, "Ongeldig scenenummer"
    end

    if not is_positive_integer(trackNumber)
        or trackNumber > TRACK_COUNT
    then
        return false, "Ongeldig tracknummer"
    end

    if not is_positive_integer(patternNumber) then
        return false, "Ongeldig patternnummer"
    end

    local state = loadState()
    local scene =
        ensureScene(state, sceneNumber)

    scene[trackNumber] = patternNumber

    saveState(state)

    return true
end


function M.getCurrentScene()
    local state = loadState()

    return state.currentScene
end


function M.setCurrentScene(sceneNumber)
    sceneNumber = tonumber(sceneNumber)

    if not is_positive_integer(sceneNumber) then
        return false, "Ongeldig scenenummer"
    end

    local state = loadState()

    ensureScene(state, sceneNumber)

    state.currentScene = sceneNumber

    saveState(state)

    return true
end


function M.getNextScene()
    local state = loadState()

    return state.nextScene
end


function M.setNextScene(sceneNumber)
    sceneNumber = tonumber(sceneNumber)

    if not is_positive_integer(sceneNumber) then
        return false, "Ongeldig scenenummer"
    end

    local state = loadState()

    ensureScene(state, sceneNumber)

    state.nextScene = sceneNumber

    saveState(state)

    return true
end


function M.activateNextScene()
    local state = loadState()

    local nextScene =
        state.nextScene
        or state.currentScene
        or 1

    ensureScene(state, nextScene)

    state.currentScene = nextScene

    saveState(state)

    return nextScene
end


function M.getSceneState()
    local state = loadState()

    -- Dit is een volledige Lua-table.
    return state
end


function M.getSerializedSceneState()
    return reaper.GetExtState(
        EXT_SECTION,
        EXT_KEY
    )
end


function M.showSceneState()
    local serialized =
        M.getSerializedSceneState()

    if serialized == "" then
        serialized =
            "Nog geen SceneState opgeslagen."
    end

    reaper.ShowMessageBox(
        serialized,
        "Pattern Launcher SceneState",
        0
    )
end


function M.resetSceneState()
    reaper.DeleteExtState(
        EXT_SECTION,
        EXT_KEY,
        true
    )

    local state = createDefaultState()

    saveState(state)

    return true
end


function M.getTrackCount()
    return TRACK_COUNT
end

function M.getxy()
local _, _, _, _, mode, resolution, val, valhw =
  reaper.get_action_context()

local note = math.floor((val / resolution) * 127 + 0.5)

 active_track = nil
local region_num = nil



local cols = {
  [0]  = 1,
  [2]  = 2,
  [3]  = 3,
  [4]  = 4,
  [5]  = 5,
  [7]  = 6,
  [9]  = 7,
  [10] = 8
}


if note == 1 then
  row = 8
  col = 7
elseif note == 2 then
  row = 8
  col = 8
else
  col = cols[note % 12]
  if not col then return end

  local base_note = 36
  row = math.floor((note - base_note) / 12) + 1
end

if row < 1 or row > 8 then return end

return row,col
end

return M
