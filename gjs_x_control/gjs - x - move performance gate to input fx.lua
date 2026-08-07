-- Move gjs: Launchpad Performance Gate from normal Track FX to Input FX.
-- Run once in the subproject where your performance tracks live.

local FX_NAME = "gjs: Launchpad Performance Gate"
local moved = 0
local added = 0

local function fx_name(track, index)
    local ok, name = reaper.TrackFX_GetFXName(track, index, "")
    return ok and name or ""
end

local function find_normal_gate(track)
    local count = reaper.TrackFX_GetCount(track)
    for i = 0, count - 1 do
        local name = fx_name(track, i)
        if name:find("Launchpad Performance Gate", 1, true) then
            return i
        end
    end
    return nil
end

local function has_input_gate(track)
    local count = reaper.TrackFX_GetRecCount(track)
    for i = 0, count - 1 do
        local idx = 0x1000000 + i
        local name = fx_name(track, idx)
        if name:find("Launchpad Performance Gate", 1, true) then
            return true
        end
    end
    return false
end

reaper.Undo_BeginBlock()

local proj = 0
local track_count = reaper.CountTracks(proj)
for t = 0, track_count - 1 do
    local track = reaper.GetTrack(proj, t)
    local normal = find_normal_gate(track)
    local input_has = has_input_gate(track)

    if normal ~= nil and not input_has then
        local rec_index = reaper.TrackFX_AddByName(track, FX_NAME, true, -1)
        if rec_index >= 0 then
            reaper.TrackFX_Delete(track, normal)
            moved = moved + 1
        end
    elseif normal == nil and not input_has then
        -- Only auto-add to record-armed tracks when there is no existing gate.
        if reaper.GetMediaTrackInfo_Value(track, "I_RECARM") > 0.5 then
            local rec_index = reaper.TrackFX_AddByName(track, FX_NAME, true, -1)
            if rec_index >= 0 then
                added = added + 1
            end
        end
    end
end

reaper.Undo_EndBlock("Move Launchpad Performance Gate to Input FX", -1)
reaper.UpdateArrange()
reaper.ShowMessageBox(
    "Performance Gate naar Input FX verplaatst: " .. moved ..
    "\\nToegevoegd aan armed tracks: " .. added,
    "GJS - X",
    0
)
