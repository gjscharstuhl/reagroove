-- gjs - RESET project content
-- Removes all media items and automation points
-- Keeps tracks/plugins/regions intact

local proj = 0

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

------------------------------------------------------------
-- Delete all media items
------------------------------------------------------------

local item_count = reaper.CountMediaItems(proj)

for i = item_count - 1, 0, -1 do
  local item = reaper.GetMediaItem(proj, i)
  local track = reaper.GetMediaItem_Track(item)

  reaper.DeleteTrackMediaItem(track, item)
end

------------------------------------------------------------
-- Delete all track automation
------------------------------------------------------------

local track_count = reaper.CountTracks(proj)

for t = 0, track_count - 1 do
  local track = reaper.GetTrack(proj, t)

  local env_count =
    reaper.CountTrackEnvelopes(track)

  for e = 0, env_count - 1 do
    local env =
      reaper.GetTrackEnvelope(track, e)

    reaper.DeleteEnvelopePointRange(
      env,
      -1000000,
      1000000
    )

    reaper.Envelope_SortPoints(env)
  end
end

------------------------------------------------------------
-- Optional: reset transport
------------------------------------------------------------

reaper.Main_OnCommand(1016, 0) -- Stop
reaper.SetEditCurPos(0, true, false)

------------------------------------------------------------
-- Finish
------------------------------------------------------------

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()

reaper.Undo_EndBlock(
  "gjs - RESET project content",
  -1
)
