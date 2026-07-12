-- gjs - Delete all items and automation
-- inside all 8 regions in all project tabs

local TOLERANCE = 0.000001
local REGION_COUNT = 8

local function get_all_regions(proj)
  local regions = {}

  local _, num_markers, num_regions =
    reaper.CountProjectMarkers(proj)

  local total = num_markers + num_regions

  for i = 0, total - 1 do
    local ok, isrgn, pos, rgnend, name, id =
      reaper.EnumProjectMarkers2(proj, i)

    if ok and isrgn then
      table.insert(regions, {
        id = id,
        start_pos = pos,
        end_pos = rgnend,
        name = name or ""
      })
    end
  end

  table.sort(regions, function(a, b)
    return a.start_pos < b.start_pos
  end)

  return regions
end

local function delete_items_inside_region(proj, region)
  local deleted = false
  local item_count = reaper.CountMediaItems(proj)

  for i = item_count - 1, 0, -1 do
    local item = reaper.GetMediaItem(proj, i)

    local item_pos =
      reaper.GetMediaItemInfo_Value(
        item,
        "D_POSITION"
      )

    local item_len =
      reaper.GetMediaItemInfo_Value(
        item,
        "D_LENGTH"
      )

    local item_end = item_pos + item_len

    local overlaps_region =
      item_end > region.start_pos + TOLERANCE and
      item_pos < region.end_pos - TOLERANCE

    if overlaps_region then
      local track = reaper.GetMediaItem_Track(item)

      reaper.DeleteTrackMediaItem(
        track,
        item
      )

      deleted = true
    end
  end

  return deleted
end

local function delete_automation_from_envelope(
  envelope,
  region_start,
  region_end
)
  local deleted = false

  -- Verwijder losse envelopepunten binnen de region.
  local point_count_before =
    reaper.CountEnvelopePointsEx(
      envelope,
      -1
    )

  reaper.DeleteEnvelopePointRangeEx(
    envelope,
    -1,
    region_start - TOLERANCE,
    region_end + TOLERANCE
  )

  local point_count_after =
    reaper.CountEnvelopePointsEx(
      envelope,
      -1
    )

  if point_count_after < point_count_before then
    deleted = true
  end

  -- Verwijder automation items die de region overlappen.
  local automation_item_count =
    reaper.CountAutomationItems(envelope)

  for ai = automation_item_count - 1, 0, -1 do
    local ai_pos =
      reaper.GetSetAutomationItemInfo(
        envelope,
        ai,
        "D_POSITION",
        0,
        false
      )

    local ai_len =
      reaper.GetSetAutomationItemInfo(
        envelope,
        ai,
        "D_LENGTH",
        0,
        false
      )

    local ai_end = ai_pos + ai_len

    local overlaps_region =
      ai_end > region_start + TOLERANCE and
      ai_pos < region_end - TOLERANCE

    if overlaps_region then
      reaper.DeleteAutomationItem(
        envelope,
        ai
      )

      deleted = true
    end
  end

  reaper.Envelope_SortPointsEx(
    envelope,
    -1
  )

  return deleted
end

local function delete_track_automation_inside_region(
  track,
  region
)
  local deleted = false
  local envelope_count =
    reaper.CountTrackEnvelopes(track)

  for i = 0, envelope_count - 1 do
    local envelope =
      reaper.GetTrackEnvelope(
        track,
        i
      )

    if envelope then
      if delete_automation_from_envelope(
        envelope,
        region.start_pos,
        region.end_pos
      ) then
        deleted = true
      end
    end
  end

  return deleted
end

local function delete_all_automation_inside_region(
  proj,
  region
)
  local deleted = false
  local track_count = reaper.CountTracks(proj)

  -- Gewone tracks, inclusief FX-envelopes.
  for i = 0, track_count - 1 do
    local track = reaper.GetTrack(proj, i)

    if delete_track_automation_inside_region(
      track,
      region
    ) then
      deleted = true
    end
  end

  -- Mastertrack, inclusief FX-envelopes.
  local master_track =
    reaper.GetMasterTrack(proj)

  if master_track then
    if delete_track_automation_inside_region(
      master_track,
      region
    ) then
      deleted = true
    end
  end

  return deleted
end

reaper.PreventUIRefresh(1)

local proj_idx = 0

while true do
  local proj = reaper.EnumProjects(proj_idx)
  if not proj then break end

  local regions = get_all_regions(proj)
  local changed = false

  reaper.Undo_BeginBlock2(proj)

  for region_nr = 1, REGION_COUNT do
    local region = regions[region_nr]

    if region then
      local items_deleted =
        delete_items_inside_region(
          proj,
          region
        )

      local automation_deleted =
        delete_all_automation_inside_region(
          proj,
          region
        )

      if items_deleted or automation_deleted then
        changed = true
      end
    end
  end

  reaper.Undo_EndBlock2(
    proj,
    changed
      and "gjs - Clear all 8 regions, items and automation"
      or "gjs - Clear all 8 regions - nothing found",
    -1
  )

  proj_idx = proj_idx + 1
end

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
