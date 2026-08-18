-- ============================================================
-- gjs - x - new_project.lua
-- Screen 5 "New Project" action.
-- Loads $HOME/ReaBox/default/Media/projlist.RPL directly,
-- then performs a full cleanup. No startup-only command here.
-- ============================================================

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*[\\/])") or ""

local clear = dofile(script_dir .. "gjs - x - clear.lua")
local M = {}

local function get_home()
    local home = os.getenv("HOME") or os.getenv("USERPROFILE")
    if not home or home == "" then
        home = (os.getenv("HOMEDRIVE") or "") .. (os.getenv("HOMEPATH") or "")
    end
    if not home or home == "" then return nil end
    return home:gsub("\\", "/")
end

local function load_default_project()
    local home = get_home()
    if not home then return false, "HOME directory niet gevonden" end

    local default_dir = home .. "/ReaBox/default"
    local rpl_file = default_dir .. "/Media/projlist.RPL"
    local f = io.open(rpl_file, "r")
    if not f then return false, "projlist.RPL niet gevonden: " .. rpl_file end

    local projects = {}
    for raw_line in f:lines() do
        local line = (raw_line or ""):gsub("\r", ""):match("^%s*(.-)%s*$")
        line = line:gsub('^"', ''):gsub('"$', '')

        if line ~= "" and line:lower():match("%.rpp$") then
            local is_absolute = line:sub(1, 1) == "/"
                or line:match("^%a:[/\\]") ~= nil
                or line:sub(1, 2) == "//"
            local rpp = is_absolute and line or (default_dir .. "/" .. line)
            rpp = rpp:gsub("\\", "/")
            if reaper.file_exists(rpp) then
                projects[#projects + 1] = rpp
            end
        end
    end
    f:close()

    if #projects == 0 then
        return false, "Geen geldige RPP-projecten gevonden in " .. rpl_file
    end

    reaper.Main_OnCommand(41898, 0)
    reaper.Main_OnCommand(40886, 0)
    reaper.Main_openProject(projects[1])

    for i = 2, #projects do
        reaper.Main_OnCommand(40859, 0)
        reaper.Main_openProject(projects[i])
    end

    reaper.Main_OnCommand(40861, 0)
    return true
end

function M.run()
    local success, error_message = load_default_project()
    if not success then return false, error_message end

    -- Do not run destructive project/cleanup work inside Screen 5's pad
    -- callback. Let the callback return first, then clean on the next cycle.
    reaper.defer(function()
        local ok, err = clear.clear_all_regions_all_projects({
            items = true,
            fx = true,
            track_mode = "all"
        })

        if ok == false and err then
            reaper.ShowConsoleMsg("ReaBox New Project cleanup failed:\n" .. tostring(err) .. "\n")
        end
    end)

    return true
end

return M
