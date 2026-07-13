local lib = dofile(
    reaper.GetResourcePath() .. "/Scripts/gjs/gjs - lib.lua"
)

local SCRIPT_ID = "GJS_PatternLauncherBlink"
local BLINK_INTERVAL = 0.25

local _, _, _, _, mode, resolution, val =
    reaper.get_action_context()

-- Note-off / release negeren
if not val or val == 0 then
    return
end

if not resolution or resolution == 0 then
    return
end

-- MIDI-noot berekenen
local note = math.floor((val / resolution) * 127 + 0.5)

if note < 36 or note > 51 then
    return
end
-- Oorspronkelijke mapping van MIDI-noot naar slot 1 t/m 16
local slot =
    (12 - math.floor((note - 36) / 4) * 4)
    + math.floor((note - 36) % 4)
    + 1

local filename = "slot_" .. tostring(slot)


if slot < 1 or slot > 16 then
    return
end

local home = os.getenv("HOME")

if not home then
    return
end

local list_path =
    home .. "/jams/" .. filename .. "/" .. filename .. ".RPL"

------------------------------------------------------------
-- RPL-bestand lezen
------------------------------------------------------------

local file = io.open(list_path, "r")

if not file then
    return
end

local projects = {}

for line in file:lines() do
    line = line:gsub("\r", "")
    line = line:match("^%s*(.-)%s*$")
    line = line:gsub('^"(.-)"$', "%1")

    if line ~= "" then
        projects[#projects + 1] = line
    end
end

file:close()

if #projects == 0 then
    return
end

------------------------------------------------------------
-- Projectlijst openen
------------------------------------------------------------

local function open_project_list()

    -- Eerst alle bestaande benoemde projecten opslaan
    local index = 0

    while true do
        local project, project_path =
            reaper.EnumProjects(index, "")

        if not project then
            break
        end

        -- Naamloze projecten overslaan om Save As-dialogen te vermijden
        if project_path and project_path ~= "" then
            reaper.Main_SaveProject(project, false)
        end

        index = index + 1
    end

    -- Alle bestaande projecttabs sluiten
    reaper.Main_OnCommand(40886, 0)

    -- Eerste project openen in de huidige tab
    reaper.Main_openProject(
        "noprompt:" .. projects[1]
    )

    -- Overige projecten in nieuwe tabs openen
    for i = 2, #projects do
        -- New project tab, ignore default template
        reaper.Main_OnCommand(41929, 0)

        reaper.Main_openProject(
            "noprompt:" .. projects[i]
        )
    end

    -- Eerste projecttab focus geven
    local first_project = reaper.EnumProjects(0, "")

    if first_project then
        reaper.SelectProjectInstance(first_project)
    end
end

-- Eerst de huidige ReaLearn/action-callback laten eindigen
reaper.defer(open_project_list)


