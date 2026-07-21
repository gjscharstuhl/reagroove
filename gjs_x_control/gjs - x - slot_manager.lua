-- ============================================================
-- gjs - x - slot_manager.lua
-- LOAD V5
--
-- Belangrijk:
-- ActiveSlot wordt ingesteld VOORDAT REAPER van project wisselt.
-- De oude scriptcontext kan namelijk verdwijnen tijdens
-- Main_openProject().
-- ============================================================

local M = {}

local HOME = os.getenv("HOME")
local JAMS_DIR = HOME and (HOME .. "/jams") or nil

local EXT_SECTION = "GJS_X"
local EXT_ACTIVE_SLOT = "ActiveSlotSession"

local function valid_slot(slot)
    slot = tonumber(slot)

    if not slot then
        return nil
    end

    slot = math.floor(slot)

    if slot < 1 or slot > 56 then
        return nil
    end

    return slot
end

local function slot_name(slot)
    return "slot_" .. tostring(slot)
end

local function slot_rpl_path(slot)
    local name = slot_name(slot)

    return JAMS_DIR
        .. "/"
        .. name
        .. "/"
        .. name
        .. ".RPL"
end

local function file_exists(path)
    local file = io.open(path, "rb")

    if file then
        file:close()
        return true
    end

    return false
end

local function read_project_list(slot)
    local file = io.open(slot_rpl_path(slot), "r")

    if not file then
        return nil,
            "Geen RPL-bestand gevonden voor slot "
            .. tostring(slot)
            .. "."
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
        return nil,
            "De projectlijst van slot "
            .. tostring(slot)
            .. " is leeg."
    end

    return projects
end

function M.get_active_slot()
    return valid_slot(
        reaper.GetExtState(
            EXT_SECTION,
            EXT_ACTIVE_SLOT
        )
    )
end

function M.can_load(slot)
    slot = valid_slot(slot)

    return slot ~= nil
       and JAMS_DIR ~= nil
       and file_exists(slot_rpl_path(slot))
end

function M.load(slot, on_loaded)
    slot = valid_slot(slot)

    if not slot or not JAMS_DIR then
        return false,
            "Ongeldig slot of HOME ontbreekt."
    end

    local projects, error_message =
        read_project_list(slot)

    if not projects then
        return false, error_message
    end

    -- Controleer alles voordat bestaande projecten worden gesloten.
    for index = 1, #projects do
        if not file_exists(projects[index]) then
            return false,
                "Project ontbreekt in slot "
                .. tostring(slot)
                .. ":\n"
                .. projects[index]
        end
    end

    local function open_projects()
        local index = 0

        -- Huidige benoemde projecten opslaan.
        while true do
            local project, project_path =
                reaper.EnumProjects(index, "")

            if not project then
                break
            end

            if project_path and project_path ~= "" then
                reaper.Main_SaveProject(
                    project,
                    false
                )
            end

            index = index + 1
        end

        -- Cruciale fix:
        -- dit moet gebeuren voordat Main_openProject de huidige
        -- project/scriptcontext vervangt.
        -- Alleen voor de huidige REAPER-sessie bewaren.
        -- Bij een nieuwe REAPER-start is er dus nog geen actief slot.
        reaper.SetExtState(
            EXT_SECTION,
            EXT_ACTIVE_SLOT,
            tostring(slot),
            false
        )

        -- Eventuele directe redraw nog in de huidige context.
        if type(on_loaded) == "function" then
            on_loaded()
        end

        -- Huidige projecttabs sluiten.
        reaper.Main_OnCommand(40886, 0)

        -- Eerste project openen.
        reaper.Main_openProject(
            "noprompt:" .. projects[1]
        )

        -- Overige projecten als tabs openen.
        for project_index = 2, #projects do
            reaper.Main_OnCommand(41929, 0)

            reaper.Main_openProject(
                "noprompt:" .. projects[project_index]
            )
        end

        -- Eerste geopende projecttab selecteren.
        local first_project =
            reaper.EnumProjects(0, "")

        if first_project then
            reaper.SelectProjectInstance(
                first_project
            )
        end
    end

    -- Laat eerst de padcallback eindigen.
    reaper.defer(open_projects)

    return true
end

return M
