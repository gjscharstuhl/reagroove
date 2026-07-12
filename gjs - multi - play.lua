

 active_track = tonumber(reaper.GetExtState("GJS_MULTI", "ActiveTrack"))
if not active_track then return end

local proj = reaper.EnumProjects(active_track)
if not proj then return end

page= tonumber(reaper.GetExtState("GJS_MULTI", "Page"))

  reaper.SetExtState("GJS_MULTI","FxRec","0",true)
 
--reaper.ShowConsoleMsg("Not recording -> normal play\n")

local function ItemOverlapsTimeSelection(item, start_time, end_time)
    local eps = 0.000001

    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = pos + len

    return item_end > start_time + eps
       and pos < end_time - eps
end

local function ItemCoversTimeSelection(item, start_time, end_time)
    local eps = 0.000001

    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = pos + len

    return pos <= start_time + eps
       and item_end >= end_time - eps
end

local function GetArmedTrack(proj)
    for i = 0, reaper.CountTracks(proj) - 1 do
        local track = reaper.GetTrack(proj, i)

        if reaper.GetMediaTrackInfo_Value(track, "I_RECARM") == 1 then
            return track
        end
    end

    return nil
end

function CleanTimeSelectionKeepLastComplete(proj)

    local track = GetArmedTrack(proj)

    if not track then return end

    local start_time, end_time =
        reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)

    if start_time == end_time then return end

    local overlapping_items = {}
    local complete_items = {}

    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)

        if ItemOverlapsTimeSelection(item, start_time, end_time) then
            overlapping_items[#overlapping_items + 1] = item

            if ItemCoversTimeSelection(item, start_time, end_time) then
                complete_items[#complete_items + 1] = item
            end
        end
    end

    if #complete_items == 0 then return end

    local keep_item = complete_items[#complete_items]

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    for _, item in ipairs(overlapping_items) do
        if item ~= keep_item then
            reaper.DeleteTrackMediaItem(track, item)
        end
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Keep last complete item and remove incomplete takes", -1)
end

 state = reaper.GetPlayStateEx(proj)

if (state & 4) == 4  then
    -- recording -> stop recording maar laat playback doorlopen
    reaper.Main_OnCommandEx(1013, 0, proj)

    reaper.defer(function()
        CleanTimeSelectionKeepLastComplete(proj)
    end)

    return
end

-- niet recording -> normale play knop
if state==0 then  reaper.Main_OnCommandEx(1007, 0, 0) end


  --local _, _, sectionID, cmdID = reaper.get_action_context()
 -- reaper.SetToggleCommandState(sectionID, cmdID, 0)

--CleanTimeSelectionKeepLastComplete(proj)
