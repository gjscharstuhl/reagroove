local M={}

function M.run()
    local projects={}
    local i=0
    while true do
        local p=reaper.EnumProjects(i,"")
        if not p then break end
        projects[#projects+1]=p
        i=i+1
    end
    local current=reaper.EnumProjects(-1,"")
    for _,p in ipairs(projects) do
        reaper.SelectProjectInstance(p)
        reaper.Main_OnCommand(40026,0)
    end
    if current then
        reaper.SelectProjectInstance(current)
    end
    reaper.Main_OnCommand(40004,0)
end

return M
