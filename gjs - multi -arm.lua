
nr = tonumber(reaper.GetExtState("GJS_MULTI", "ActiveTrack"))
page= tonumber(reaper.GetExtState("GJS_MULTI", "Page"))
    
 function cleararm(proj)
   for i=0,reaper.CountTracks()-1 do
     local tr=reaper.GetTrack(proj, i)
       if tr then reaper.SetMediaTrackInfo_Value(tr,"I_RECARM", 0) end
     end
    
 end
 
 
function arm(nr,page)
  

  -- tabs 2 t/m 9 = tracks 1 t/m 8
  for tab = 2, 9 do
    local proj = reaper.EnumProjects(tab - 1)

    if proj then
      mytracknr = tab - 1
      cleararm(proj) 
      if page==1 then
        if mytracknr==nr then
          a=1
          track=reaper.GetTrack(proj, 0) -- eerste track in dat subproject
          reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 1)
        end
      elseif page==2 then
        if mytracknr==6 or  mytracknr==7 then
          track=reaper.GetTrack(proj, 1) -- eerste track in dat subproject
          reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 1)
        end
      
      end
    end
    

  end
end

arm(nr,page)
