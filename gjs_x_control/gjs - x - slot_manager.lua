-- ============================================================
-- gjs - x - slot_manager.lua
-- LOAD/SAVE V6
--
-- Belangrijk:
-- ActiveSlot wordt ingesteld VOORDAT REAPER van project wisselt.
-- De oude scriptcontext kan namelijk verdwijnen tijdens
-- Main_openProject().
-- ============================================================

local M = {}

local scene_api = include("gjs - scene_api.lua")
local playlist_api = include("gjs - playlist_api.lua")

local HOME = os.getenv("HOME") or os.getenv("USERPROFILE")
if not HOME then
    local drive = os.getenv("HOMEDRIVE")
    local path = os.getenv("HOMEPATH")
    if drive and path then HOME = drive .. path end
end
local REABOX_DIR = HOME and (HOME .. "/ReaBox") or nil

local EXT_SECTION = "GJS_X"
local EXT_ACTIVE_SLOT = "ActiveSlotSession"

local FX_MAPPING_FILENAME = "fx_mapping.ini"

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

    return REABOX_DIR
        .. "/"
        .. name
        .. "/"
        .. name
        .. ".RPL"
end


local function slot_config_path(slot)
    return REABOX_DIR
        .. "/"
        .. slot_name(slot)
        .. "/config.txt"
end

local function trim(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

local function write_config(slot)
    local path = slot_config_path(slot)
    local file = io.open(path, "w")

    if not file then
        return false,
            "Kon config.txt niet schrijven:\n"
            .. path
    end

    file:write("VERSION=1\n\n")
    file:write("[SCENES]\n")

    local scenelist = scene_api.GetSceneList()

    for scene_nr = 1, 16 do
        local saved_scene = scenelist[scene_nr]
        local patternlist =
            saved_scene and saved_scene.patternlist

        if type(patternlist) == "table"
        and #patternlist >= 8 then
            file:write(
                tostring(scene_nr),
                "=",
                table.concat({
                    tostring(patternlist[1]),
                    tostring(patternlist[2]),
                    tostring(patternlist[3]),
                    tostring(patternlist[4]),
                    tostring(patternlist[5]),
                    tostring(patternlist[6]),
                    tostring(patternlist[7]),
                    tostring(patternlist[8])
                }, ","),
                "\n"
            )
        end
    end

    file:write("\n[PLAYLIST]\n")

    local slots = playlist_api.GetSlots()

    for playlist_slot = 1,
        playlist_api.GetSlotCount() do
        local scene_nr = slots[playlist_slot]

        if scene_nr then
            file:write(
                tostring(playlist_slot),
                "=",
                tostring(scene_nr),
                "\n"
            )
        end
    end

    file:close()
    return true
end

local function read_patternlist(value)
    local result = {}

    for token in tostring(value or ""):gmatch("[^,]+") do
        local number = tonumber(trim(token))

        if not number then
            return nil
        end

        number = math.floor(number)

        if number < 1 or number > 8 then
            return nil
        end

        result[#result + 1] = number
    end

    if #result ~= 8 then
        return nil
    end

    return result
end

local function read_config(slot)
    scene_api.Clear()
    playlist_api.ClearAll()

    local path = slot_config_path(slot)
    local file = io.open(path, "r")

    -- Oude slots zonder config.txt blijven gewoon laadbaar.
    if not file then
        return true
    end

    local section = nil
    local scenelist = scene_api.GetSceneList()

    for raw_line in file:lines() do
        local line = trim(raw_line:gsub("\r", ""))

        if line ~= ""
        and line:sub(1, 1) ~= "#"
        and line:sub(1, 1) ~= ";" then
            local section_name =
                line:match("^%[([^%]]+)%]$")

            if section_name then
                section = section_name:upper()
            else
                local key, value =
                    line:match("^([^=]+)=(.*)$")

                if key then
                    key = trim(key)
                    value = trim(value)

                    if section == "SCENES" then
                        local scene_nr = tonumber(key)
                        local patternlist =
                            read_patternlist(value)

                        if scene_nr and patternlist then
                            scene_nr = math.floor(scene_nr)

                            if scene_nr >= 1
                            and scene_nr <= 16 then
                                scenelist[scene_nr] = {
                                    current = nil,
                                    next = nil,
                                    patternlist = patternlist
                                }
                            end
                        end
                    elseif section == "PLAYLIST" then
                        local playlist_slot = tonumber(key)
                        local scene_nr = tonumber(value)

                        if playlist_slot and scene_nr then
                            playlist_api.Set(
                                math.floor(playlist_slot),
                                math.floor(scene_nr)
                            )
                        end
                    end
                end
            end
        end
    end

    file:close()
    return true
end

local function remove_old_project_files(directory)
    local filenames = {}
    local index = 0

    while true do
        local filename =
            reaper.EnumerateFiles(directory, index)

        if not filename then
            break
        end

        filenames[#filenames + 1] = filename
        index = index + 1
    end

    for _, filename in ipairs(filenames) do
        -- Alleen oude actuele projectbestanden verwijderen.
        -- REAPER-back-ups zoals .rpp-bak blijven bestaan.
        if filename:lower():match("%.rpp$") then
            os.remove(directory .. "/" .. filename)
        end
    end
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


local function read_project_list_file(rpl_path, base_dir)
    local file = io.open(rpl_path, "r")
    if not file then
        return nil, "RPL-bestand niet gevonden: " .. tostring(rpl_path)
    end

    local projects = {}
    for line in file:lines() do
        line = line:gsub("\r", "")
        line = line:match("^%s*(.-)%s*$")
        line = line:gsub('^"(.-)"$', "%1")

        if line ~= "" then
            local is_absolute = line:sub(1, 1) == "/"
                or line:match("^%a:[/\\]") ~= nil
                or line:sub(1, 2) == "//"
            local path = is_absolute and line or ((base_dir or "") .. "/" .. line)
            path = path:gsub("\\", "/")
            projects[#projects + 1] = path
        end
    end
    file:close()

    if #projects == 0 then
        return nil, "Projectlijst is leeg: " .. tostring(rpl_path)
    end
    return projects
end

local function open_project_list_like_slot(projects, on_before_open, on_after_open)
    for index = 1, #projects do
        if not file_exists(projects[index]) then
            return false, "Project ontbreekt:\n" .. projects[index]
        end
    end

    local function open_projects()
        local index = 0
        while true do
            local project, project_path = reaper.EnumProjects(index, "")
            if not project then break end
            if project_path and project_path ~= "" then
                reaper.Main_SaveProject(project, false)
            end
            index = index + 1
        end

        if type(on_before_open) == "function" then on_before_open() end

        reaper.Main_OnCommand(40886, 0)
        reaper.Main_openProject("noprompt:" .. projects[1])
        for project_index = 2, #projects do
            reaper.Main_OnCommand(41929, 0)
            reaper.Main_openProject("noprompt:" .. projects[project_index])
        end

        local first_project = reaper.EnumProjects(0, "")
        if first_project then reaper.SelectProjectInstance(first_project) end

        if type(on_after_open) == "function" then
            reaper.defer(on_after_open)
        end
    end

    reaper.defer(open_projects)
    return true
end

function M.load_rpl(rpl_path, base_dir, on_after_open)
    local projects, err = read_project_list_file(rpl_path, base_dir)
    if not projects then return false, err end
    return open_project_list_like_slot(projects, nil, on_after_open)
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
       and REABOX_DIR ~= nil
       and file_exists(slot_rpl_path(slot))
end

function M.load(slot, on_loaded)
    slot = valid_slot(slot)

    if not slot or not REABOX_DIR then
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

    local config_ok, config_error =
        read_config(slot)

    if not config_ok then
        return false, config_error
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
-- Slaat alle geopende projecttabs op in ~/ReaBox/slot_N/ en schrijft
-- slot_N.RPL. De bestaande load- en LED-logica blijft ongewijzigd.
-- ============================================================

local function slot_dir_path(slot)
    return REABOX_DIR .. "/" .. slot_name(slot)
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

local function directory_name(path)
    path = normalize_path(path)
    return path:match("^(.*)/[^/]+$")
end

local function find_fx_mapping_source(projects)
    -- Zoek het mappingbestand in de oorspronkelijke projectmap.
    -- Dit moet gebeuren voordat Main_SaveProjectEx() de projecten naar
    -- de nieuwe slotmap verplaatst.
    for index = 1, #projects do
        local project_path = projects[index].original_path

        if project_path and project_path ~= "" then
            local project_directory = directory_name(project_path)

            if project_directory then
                local candidate =
                    project_directory .. "/" .. FX_MAPPING_FILENAME

                if file_exists(candidate) then
                    return candidate
                end
            end
        end
    end

    return nil
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

    if not slot or not REABOX_DIR then
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

    -- Bewaar de bron voordat Main_SaveProjectEx() de projectpaden wijzigt.
    local fx_mapping_source = find_fx_mapping_source(projects)

    local directory = slot_dir_path(slot)
    local media_directory = directory .. "/Media"
    local fx_mapping_destination =
        directory .. "/" .. FX_MAPPING_FILENAME

    reaper.RecursiveCreateDirectory(REABOX_DIR, 0)
    reaper.RecursiveCreateDirectory(directory, 0)
    reaper.RecursiveCreateDirectory(media_directory, 0)

    -- Houd de slotmap schoon:
    -- verwijder oude .rpp-bestanden en schrijf alleen de huidige tabs.
    -- .rpp-bak blijft behouden.
    remove_old_project_files(directory)

    -- Neem de Page 3 FX-mapping mee naar het nieuwe slot.
    -- Bij opslaan over hetzelfde slot staat bron en bestemming al gelijk.
    if fx_mapping_source then
        if normalize_path(fx_mapping_source)
            ~= normalize_path(fx_mapping_destination) then
            if not copy_file(
                fx_mapping_source,
                fx_mapping_destination
            ) then
                return false,
                    "Kon FX-mapping niet kopieren:\n"
                    .. fx_mapping_source
            end
        end
    else
        -- Geen mapping in de bron: voorkom dat een oude mapping uit een
        -- eerder opgeslagen inhoud van dit doelslot blijft rondhangen.
        os.remove(fx_mapping_destination)
    end

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

    local config_ok, config_error =
        write_config(slot)

    if not config_ok then
        return false, config_error
    end

    return true
end

return M
