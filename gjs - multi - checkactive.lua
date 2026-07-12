local lib = dofile(reaper.GetResourcePath() .. "/Scripts/gjs/gjs - lib.lua")

 currenttabnr = lib.get_current_project_tab_number()
 mytracknr = currenttabnr - 1

local armed = false


function onlyarmtrack(proj,track,nr,mytracknr)
  for i=0,reaper.CountTracks()-1 do
    local tr=reaper.GetTrack(proj, i)
      if tr then reaper.SetMediaTrackInfo_Value(tr,"I_RECARM", 0) end
    end
    if nr==mytracknr and track  then reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 1)  end
    oa=nr
    ob =mytracknr
end

function loop()
   nr = tonumber(reaper.GetExtState("GJS_MULTI", "ActiveTrack"))

  -- tabs 2 t/m 9 = tracks 1 t/m 8
  for tab = 2, 9 do
    local proj = reaper.EnumProjects(tab - 1)

    if proj then
      local mytracknr = tab - 1
       page= tonumber(reaper.GetExtState("GJS_MULTI", "Page"))
      local track
      if page==2 then
        if mytracknr==6 or mytracknr==7 then
          track = reaper.GetTrack(proj, 1) -- 2e track in dat subproject
        end
      else 
        track=reaper.GetTrack(proj, 0) -- eerste track in dat subproject
      end
    
    
      if track then   onlyarmtrack(proj,track,nr,mytracknr) end
      
   
    end
  end

  reaper.defer(loop)
end

loop()


