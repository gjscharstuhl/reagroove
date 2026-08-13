local M = {}

local function get_project(subproject_number)
    subproject_number = tonumber(subproject_number)
    if not subproject_number then
        return nil
    end

    subproject_number = math.floor(subproject_number)

    if subproject_number < 1 or subproject_number > 8 then
        return nil
    end

    -- Natural visible-tab flow:
    -- ActiveTrack 1 -> REAPER project 0
    -- ...
    -- ActiveTrack 8 -> REAPER project 7
    return reaper.EnumProjects(subproject_number - 1, "")
end


local trackman = {
    active = 1,
    previous = 1,
    armed = {
        {}, {}, {}, {}, {}, {}, {}, {}
    }
}

-- Functie om een track toe te voegen aan een subproject
function M.insert(subproj, track)
    table.insert(trackman.armed[subproj], track)
    return true
end

-- Functie om alle tracks in een subproject te wissen
function M.clear(subproj)
    trackman.armed[subproj] = {}
end

function M.GetArmedTracks(subproj)
  M.clear(subproj)
  local sp=get_project(subproj)
  local count=reaper.CountTracks(sp)
  for index = 0, count - 1 do
    local tr=reaper.GetTrack(sp,index)
    if  reaper.GetMediaTrackInfo_Value(tr, "I_RECARM")>0  then M.insert(subproj,index) end
    --reaper.ShowConsoleMsg("tr:"..index.."val:"..reaper.GetMediaTrackInfo_Value(tr, "I_RECARM").."\n")
  end

end

function M.Armtracks(subproj)
  local sp=get_project(subproj)
   for i = 1, #trackman.armed[subproj] do
      local index=trackman.armed[subproj][i]
      local tr=reaper.GetTrack(subproj,index)
      reaper.ShowConsoleMsg("index:"..index.."\n")
      
      reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 1)

   
   end
end


function M.DisArmAllTracks(subproj)

 local sp=get_project(subproj)
 local count=reaper.CountTracks(sp)
 for index = 0, count - 1 do
   local tr=reaper.GetTrack(sp,index)
   reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 0)
   --reaper.ShowConsoleMsg("tr:"..index.."val:"..reaper.GetMediaTrackInfo_Value(tr, "I_RECARM").."\n")
 end

  
end

-- Functie om alle tracks te tonen
function M.show()
    for i = 1, 8 do
        for j = 1, #trackman.armed[i] do
            reaper.ShowConsoleMsg("proj " .. i .. ": " .. trackman.armed[i][j].."\n")
        end
       
    end

end



-- ===== TESTCODE =====
--M.GetArmedTracks(2)
--trackman.armed[2]={1,2,4}
--M.Armtracks(2)
--M.DisArmAllTracks(2)
-- M.show()


