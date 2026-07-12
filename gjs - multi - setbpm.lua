-- Sync tempo of project tabs 2 through 9 to tab 1
-- REAPER ReaScript Lua

-- Get project in first tab
local main_proj = reaper.EnumProjects(0, "")
if not main_proj then
  reaper.ShowMessageBox("Geen project gevonden in tabblad 1.", "Tempo sync", 0)
  return
end

-- Get tempo from tab 1 at project start
local tempo = reaper.Master_GetTempo(main_proj)

reaper.Undo_BeginBlock()

-- Apply tempo to tabs 2 through 9
for i = 1, 8 do
  local proj = reaper.EnumProjects(i, "")
  if proj then
    -- Set project tempo at time 0
    reaper.SetTempoTimeSigMarker(
      proj,
      -1,        -- create new marker if needed
      0,         -- time position
      -1,        -- measure position auto
      -1,        -- beat position auto
      tempo,     -- BPM
      0,         -- numerator unchanged/default
      0,         -- denominator unchanged/default
      false      -- not linear tempo transition
    )
  end
end

reaper.Undo_EndBlock("Sync tempo tabs 2-9 to tab 1", -1)

reaper.UpdateTimeline()
