-- Startup_RPL.lua
reaper.Main_OnCommand(41898, 0)
reaper.Main_OnCommand(40886, 0)

local rpl_file = "/home/gj/.config/REAPER/ProjectTemplates/live-lauchpadx-multi/Media/projlist.RPL"

local f = io.open(rpl_file, "r")
if not f then return end

local projects = {}

for line in f:lines() do
    local rpp = line:match("(.+%.RPP)")
              or line:match("(.+%.rpp)")

    if rpp then
        rpp = rpp:gsub('^"', ''):gsub('"$', '')
        if reaper.file_exists(rpp) then
            table.insert(projects, rpp)
        end
    end
end

f:close()

if #projects == 0 then return end

reaper.Main_openProject(projects[1])

for i = 2, #projects do
    reaper.Main_OnCommand(40859, 0) -- New project tab
    reaper.Main_openProject(projects[i])
end

-- terug naar tab 1
reaper.Main_OnCommand(40861, 0)


-- script 1
local cmd1 = reaper.NamedCommandLookup("_RS24fe6e7c8f1592a2c6495b4dad0459c4c4f39ff9")
if cmd1 ~= 0 then
    reaper.Main_OnCommand(cmd1, 0)
end

-- script 2
local cmd2 = reaper.NamedCommandLookup("_RS07be46009cc5cd915d3faeafb854c96afcb1f07c")
if cmd2 ~= 0 then
    reaper.Main_OnCommand(cmd2, 0)
end


