local lib = dofile(reaper.GetResourcePath() .. "/Scripts/gjs/gjs - lib.lua")

 currenttabnr = lib.get_current_project_tab_number()
 mytracknr = target

local armed = false

function loop()
   nr = lib.target("tracks")

  -- tabs 2 t/m 9 = tracks 1 t/m 8
  for tab = 2, 9 do
    local proj = reaper.EnumProjects(tab - 1)

    if proj then
      local mytracknr = tab - 1
      local track = reaper.GetTrack(proj, 0) -- eerste track in dat subproject

      if track then
        if nr == mytracknr then
          reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 1)
        else
          reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 0)
        end
      end
    end
  end
  return
end

loop()


