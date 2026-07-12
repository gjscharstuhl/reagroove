-- gjs - Set time selection to region number 3
-- Recording friendly: does not move cursor or transport

local function get_selected_region_number()

    local sel = reaper.GetSelectedTrack(0, 0)
    if not sel then return nil end

    local regions_folder = nil
    local regions_idx = nil

    -- zoek folder Regions
    for i = 0, reaper.CountTracks(0)-1 do
        local tr = reaper.GetTrack(0, i)
        local _, name = reaper.GetTrackName(tr)

        if name:lower() == "regions" then
            regions_folder = tr
            regions_idx = i
            break
        end
    end

    if not regions_folder then return nil end

    local sel_idx = reaper.CSurf_TrackToID(sel, false) - 1

    -- eerste child = region1
    local region_num = sel_idx - regions_idx

    if region_num >= 1 and region_num <= 8 then
        return region_num
    end

    return nil
end

local target_region_number =  get_selected_region_number()

local _, num_markers, num_regions = reaper.CountProjectMarkers(0)

for i = 0, num_markers + num_regions - 1 do
  local retval, is_region, pos, rgnend, name, markrgnindexnumber =
    reaper.EnumProjectMarkers(i)

  if is_region and markrgnindexnumber == target_region_number then
    reaper.GetSet_LoopTimeRange(true, false, pos, rgnend, false)
    reaper.UpdateArrange()
    return
  end
end
