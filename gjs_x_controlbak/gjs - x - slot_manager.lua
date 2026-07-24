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


-- ============================================================
-- SAVE
-- Slaat alle geopende projecttabs op in ~/jams/slot_N/ en schrijft
-- slot_N.RPL. De bestaande load- en LED-logica blijft ongewijzigd.
-- ============================================================

local function slot_dir_path(slot)
    return JAMS_DIR .. "/" .. slot_name(slot)
end

local function basename(path)
    return path:match("([^/\\]+)$") or path
end

local function strip_extension(name)
    return (name:gsub("%.[^%.]+$", ""))
end


local function normalize_path(path)
    return (path or ""):gsub("\\", "/")
end

local function copy_file(source_path, destination_path)
    local source = io.open(source_path, "rb")

    if not source then
        return false
    end

    local destination = io.open(destination_path, "wb")

    if not destination then
        source:close()
        return false
    end

    while true do
        local chunk = source:read(1024 * 1024)

        if not chunk then
            break
        end

        destination:write(chunk)
    end

    source:close()
    destination:close()

    return true
end

local function split_filename(name)
    local stem, extension = name:match("^(.*)(%.[^%.]*)$")

    if not stem then
        return name, ""
    end

    return stem, extension
end

local function unique_media_path(media_directory, filename, reserved)
    local stem, extension = split_filename(filename)
    local candidate = media_directory .. "/" .. filename
    local counter = 1

    while reserved[normalize_path(candidate)] do
        candidate = string.format(
            "%s/%s-%02d%s",
            media_directory,
            stem,
            counter,
            extension
        )
        counter = counter + 1
    end

    reserved[normalize_path(candidate)] = true
    return candidate
end

local function safe_name(name)
    name = name:gsub("[/\\:%*%?\"<>|]", "_")
    name = name:gsub("^%s+", ""):gsub("%s+$", "")

    if name == "" then
        return "project"
    end

    return name
end

function M.save(slot)
    slot = valid_slot(slot)

    if not slot or not JAMS_DIR then
        return false,
            "Ongeldig slot of HOME ontbreekt."
    end

    local projects = {}
    local index = 0

    while true do
        local project, project_path =
            reaper.EnumProjects(index, "")

        if not project then
            break
        end

        projects[#projects + 1] = {
            project = project,
            original_path = project_path or "",
            number = index + 1
        }

        index = index + 1
    end

    if #projects == 0 then
        return false,
            "Er zijn geen geopende projecten om op te slaan."
    end

    local directory = slot_dir_path(slot)
    local media_directory = directory .. "/media"

    reaper.RecursiveCreateDirectory(JAMS_DIR, 0)
    reaper.RecursiveCreateDirectory(directory, 0)
    reaper.RecursiveCreateDirectory(media_directory, 0)

    local saved_paths = {}
    local copied_sources = {}
    local reserved_destinations = {}

    reaper.PreventUIRefresh(1)

    for project_index = 1, #projects do
        local entry = projects[project_index]
        local item_count = reaper.CountMediaItems(entry.project)

        for item_index = 0, item_count - 1 do
            local item = reaper.GetMediaItem(entry.project, item_index)
            local take_count = reaper.CountTakes(item)

            for take_index = 0, take_count - 1 do
                local take = reaper.GetTake(item, take_index)

                if take and not reaper.TakeIsMIDI(take) then
                    local source = reaper.GetMediaItemTake_Source(take)
                    local source_path = reaper.GetMediaSourceFileName(source, "")

                    if source_path and source_path ~= "" then
                        local source_key = normalize_path(source_path)
                        local destination = copied_sources[source_key]

                        if not destination then
                            if source_key:sub(1, #normalize_path(media_directory) + 1)
                                == normalize_path(media_directory) .. "/" then
                                destination = source_path
                            else
                                destination = unique_media_path(
                                    media_directory,
                                    basename(source_path),
                                    reserved_destinations
                                )

                                if not copy_file(source_path, destination) then
                                    reaper.PreventUIRefresh(-1)
                                    reaper.UpdateArrange()

                                    return false,
                                        "Kon media niet kopieren:\n"
                                        .. source_path
                                end
                            end

                            copied_sources[source_key] = destination
                        end

                        if normalize_path(destination) ~= source_key then
                            local new_source =
                                reaper.PCM_Source_CreateFromFile(destination)

                            if not new_source then
                                reaper.PreventUIRefresh(-1)
                                reaper.UpdateArrange()

                                return false,
                                    "Kon gekopieerde media niet openen:\n"
                                    .. destination
                            end

                            reaper.SetMediaItemTake_Source(take, new_source)
                        end
                    end
                end
            end
        end

        local project_name

        if entry.original_path ~= "" then
            project_name = strip_extension(
                basename(entry.original_path)
            )
        else
            project_name = string.format(
                "project-%02d",
                entry.number
            )
        end

        project_name = safe_name(project_name)

        local destination = string.format(
            "%s/%02d-%s.rpp",
            directory,
            entry.number,
            project_name
        )

        reaper.Main_SaveProjectEx(
            entry.project,
            destination,
            0
        )

        if not file_exists(destination) then
            reaper.PreventUIRefresh(-1)
            reaper.UpdateArrange()

            return false,
                "Kon project niet opslaan:\n"
                .. destination
        end

        saved_paths[#saved_paths + 1] = destination
    end

    reaper.PreventUIRefresh(-1)
    reaper.UpdateArrange()

    local list_path = slot_rpl_path(slot)
    local list_file = io.open(list_path, "w")

    if not list_file then
        return false,
            "Kon RPL-bestand niet schrijven:\n"
            .. list_path
    end

    for project_index = 1, #saved_paths do
        list_file:write(
            saved_paths[project_index],
            "\n"
        )
    end

    list_file:close()

    return true
end

return M
