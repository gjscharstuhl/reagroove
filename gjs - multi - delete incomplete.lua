-- Delete incomplete items in time selection, then glue complete items
-- target project via GJS_MULTI / ActiveTrack


reaper.Main_OnCommandEx(1007, 0, 0) -- play

local active_track = tonumber(reaper.GetExtState("GJS_MULTI", "ActiveTrack"))
if not active_track then return end

local proj = reaper.EnumProjects(active_track)
if not proj then return end

function GetItemsInTimeSelection(proj)
    local items = {}
    local eps = 0.0000001

    local start_time, end_time =
        reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)

    if start_time == end_time then
        return items
    end

    for i = 0, reaper.CountMediaItems(proj) - 1 do
        local item = reaper.GetMediaItem(proj, i)

        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local item_end = pos + len

        local overlaps =
            item_end > start_time + eps and
            pos < end_time - eps

        if overlaps then
            items[#items + 1] = item
        end
    end

    return items
end

local start_time, end_time =
    reaper.GetSet_LoopTimeRange2(proj, false, false, 0, 0, false)

if start_time == end_time then
    return
end

reaper.Undo_BeginBlock2(proj)
reaper.PreventUIRefresh(1)

-- Unselect all items
for i = 0, reaper.CountMediaItems(proj) - 1 do
    local item = reaper.GetMediaItem(proj, i)
    reaper.SetMediaItemSelected(item, false)
end

local items = GetItemsInTimeSelection(proj)

local delothers = false

for i = #items, 1, -1 do
    local item = items[i]

    if reaper.ValidatePtr2(proj, item, "MediaItem*") then

        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local item_end = pos + len

        local covers_selection =
            pos <= start_time and item_end >= end_time

        if (not covers_selection) or delothers then
            reaper.DeleteTrackMediaItem(
                reaper.GetMediaItem_Track(item),
                item
            )

        else
            reaper.SetMediaItemSelected(item, true)
            delothers = true
        end
    end
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()

reaper.Undo_EndBlock2(
    proj,
    "Delete incomplete items and glue complete items",
    -1
)
