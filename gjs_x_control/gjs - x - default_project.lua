-- ============================================================
-- gjs - x - default_project.lua
-- Shared portable default-project loader for __startup.lua
-- and Screen 5.
--
-- Expected layout:
--   $HOME/ReaBox/default/Media/projlist.RPL
--
-- Entries in projlist.RPL may be relative to $HOME/ReaBox/default,
-- or absolute Linux/Windows paths.
-- ============================================================

local M = {}

local function get_home()
    local home = os.getenv("HOME") or os.getenv("USERPROFILE")

    if not home or home == "" then
        local drive = os.getenv("HOMEDRIVE") or ""
        local path = os.getenv("HOMEPATH") or ""
        home = drive .. path
    end

    if not home or home == "" then
        return nil
    end

    return home:gsub("\\", "/")
end

local function trim(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

local function is_absolute(path)
    return path:sub(1, 1) == "/"
        or path:match("^%a:[/\\]") ~= nil
        or path:sub(1, 2) == "//"
end

function M.load()
    local home = get_home()
    if not home then
        return false, "HOME directory niet gevonden"
    end

    local default_dir = home .. "/ReaBox/default"
    local rpl_file = default_dir .. "/Media/projlist.RPL"

    local file = io.open(rpl_file, "r")
    if not file then
        return false, "projlist.RPL niet gevonden: " .. rpl_file
    end

    local projects = {}

    for raw_line in file:lines() do
        local line = trim(raw_line:gsub("\r", ""))
        line = line:gsub('^"', ''):gsub('"$', '')

        if line ~= "" and line:lower():match("%.rpp$") then
            local rpp

            if is_absolute(line) then
                rpp = line
            else
                rpp = default_dir .. "/" .. line
            end

            rpp = rpp:gsub("\\", "/")

            if reaper.file_exists(rpp) then
                projects[#projects + 1] = rpp
            end
        end
    end

    file:close()

    if #projects == 0 then
        return false, "Geen geldige RPP-projecten gevonden in " .. rpl_file
    end

    -- Same preparation as the original startup script.
    reaper.Main_OnCommand(41898, 0)
    reaper.Main_OnCommand(40886, 0)

    reaper.Main_openProject(projects[1])

    for i = 2, #projects do
        reaper.Main_OnCommand(40859, 0) -- New project tab
        reaper.Main_openProject(projects[i])
    end

    -- Back to tab 1.
    reaper.Main_OnCommand(40861, 0)

    return true
end

return M
