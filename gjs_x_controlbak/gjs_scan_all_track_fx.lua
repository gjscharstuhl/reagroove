-- ============================================================
-- GJS-X - Scan FX parameters in the first 8 open subprojects
--
-- Run this script from the main project tab.
-- For every other open project tab, it scans:
--   1. the first normal track
--   2. the subproject master track
--
-- The first-track sections keep the old TrackN.FXN names so
-- existing mappings remain usable. Master FX use TrackN.Master.FXN.
--
-- Enter F1..F8 or B1..B8 after the desired parameters.
-- Existing assignments are preserved when scanning again.
-- ============================================================

local MAX_SUBPROJECTS = 8
local OUTPUT_FILENAME = "gjs_page3_fx_mapping.ini"

local function trim(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

local function clean_label(value)
    value = trim(value)
    value = value:gsub("[\r\n]", " ")
    value = value:gsub("=", "-")
    value = value:gsub("%[", "(")
    value = value:gsub("%]", ")")
    return value
end

local function basename_without_extension(path)
    local name = (path or ""):match("([^/\\]+)$") or ""
    return name:gsub("%.[Rr][Pp][Pp]$", "")
end

local function get_track_name(track)
    local _, name = reaper.GetTrackName(track)
    return clean_label(name)
end

local function dirname(path)
    return (path or ""):match("^(.*)[/\\]")
end

local function output_path()
    local _, project_file = reaper.EnumProjects(-1, "")
    local project_dir = dirname(project_file)
    local separator = package.config:sub(1, 1)

    if project_dir and project_dir ~= "" then
        return project_dir .. separator .. OUTPUT_FILENAME
    end

    return reaper.GetResourcePath() .. separator .. OUTPUT_FILENAME
end

local function parse_existing_assignments(path)
    local assignments = {}
    local file = io.open(path, "r")

    if not file then
        return assignments
    end

    local section = nil

    for line in file:lines() do
        local parsed_section = line:match("^%s*%[([^%]]+)%]%s*$")

        if parsed_section then
            section = parsed_section
            assignments[section] = assignments[section] or {}
        elseif section and not line:match("^%s*[;#]") then
            local key, value = line:match("^%s*([^=]+)%s*=%s*([^;#]*)")

            if key then
                key = trim(key)
                value = trim(value):upper()

                if value:match("^[FB][1-8]$") then
                    assignments[section][key] = value
                elseif value:match("^[1-8]$") then
                    -- Preserve mappings made with the first scanner.
                    assignments[section][key] = "F" .. value
                end
            end
        end
    end

    file:close()
    return assignments
end

local function unique_parameter_key(parameter_name, parameter_index, used)
    local base = clean_label(parameter_name)

    if base == "" then
        base = "Parameter " .. tostring(parameter_index + 1)
    end

    local key = base
    local duplicate = 2

    while used[key] do
        key = base .. " (" .. duplicate .. ")"
        duplicate = duplicate + 1
    end

    used[key] = true
    return key
end

local function collect_open_subprojects(main_project)
    local projects = {}
    local index = 0

    while true do
        local project, project_file = reaper.EnumProjects(index, "")

        if not project then
            break
        end

        if project ~= main_project then
            projects[#projects + 1] = {
                project = project,
                path = project_file or ""
            }

            if #projects >= MAX_SUBPROJECTS then
                break
            end
        end

        index = index + 1
    end

    return projects
end

local function write_fx_sections(file, track, section_prefix, existing)
    local fx_count = reaper.TrackFX_GetCount(track)

    if fx_count == 0 then
        file:write("; No FX found.\n\n")
        return
    end

    for fx_index = 0, fx_count - 1 do
        local _, fx_name = reaper.TrackFX_GetFXName(track, fx_index, "")
        fx_name = clean_label(fx_name)

        local section = string.format(
            "%s.FX%d",
            section_prefix,
            fx_index + 1
        )

        file:write("[" .. section .. "]\n")
        file:write("; FX: " .. (fx_name ~= "" and fx_name or "Unnamed FX") .. "\n")

        local parameter_count = reaper.TrackFX_GetNumParams(track, fx_index)
        local used_keys = {}

        if parameter_count == 0 then
            file:write("; No parameters found.\n")
        end

        for parameter_index = 0, parameter_count - 1 do
            local _, parameter_name = reaper.TrackFX_GetParamName(
                track,
                fx_index,
                parameter_index,
                ""
            )

            local key = unique_parameter_key(
                parameter_name,
                parameter_index,
                used_keys
            )
            local old_value = ""

            if existing[section] and existing[section][key] then
                old_value = existing[section][key]
            end

            file:write(key .. "=" .. old_value .. "\n")
        end

        file:write("\n")
    end
end

local function write_mapping(path, subprojects, existing)
    local file, error_message = io.open(path, "w")

    if not file then
        return false, error_message
    end

    file:write("; ============================================================\n")
    file:write("; GJS-X plugin mapping\n")
    file:write("; F1..F8 = vertical faders\n")
    file:write("; B1..B8 = balance controls\n")
    file:write("; Leave unused parameters empty.\n")
    file:write("; Running the scanner again preserves existing assignments.\n")
    file:write("; ============================================================\n\n")

    for slot = 1, MAX_SUBPROJECTS do
        local entry = subprojects[slot]

        file:write("; ------------------------------------------------------------\n")

        if not entry then
            file:write(string.format("; SUBPROJECT %d - not open\n", slot))
            file:write("; ------------------------------------------------------------\n\n")
        else
            local project = entry.project
            local project_name = basename_without_extension(entry.path)

            if project_name == "" then
                project_name = "Unsaved subproject"
            end

            file:write(string.format(
                "; SUBPROJECT %d - %s\n",
                slot,
                clean_label(project_name)
            ))
            file:write("; ------------------------------------------------------------\n\n")

            -- First normal track in the subproject.
            if reaper.CountTracks(project) > 0 then
                local first_track = reaper.GetTrack(project, 0)
                local first_track_name = get_track_name(first_track)

                file:write("; FIRST TRACK: " ..
                    (first_track_name ~= "" and first_track_name or "Unnamed track") ..
                    "\n\n")

                -- Keep TrackN.FXN for compatibility with the first scanner.
                write_fx_sections(
                    file,
                    first_track,
                    "Track" .. slot,
                    existing
                )
            else
                file:write("; FIRST TRACK: no track found.\n\n")
            end

            -- Master FX in the same subproject.
            local master_track = reaper.GetMasterTrack(project)
            file:write("; MASTER TRACK\n\n")
            write_fx_sections(
                file,
                master_track,
                "Track" .. slot .. ".Master",
                existing
            )
        end
    end

    file:close()
    return true
end

local main_project = reaper.EnumProjects(-1, "")
local subprojects = collect_open_subprojects(main_project)

if #subprojects == 0 then
    reaper.MB(
        "No other open project tabs were found.\n\n" ..
        "Open the subprojects as project tabs and run the scanner " ..
        "from the main project tab.",
        "GJS-X FX scanner",
        0
    )
    return
end

local path = output_path()
local existing = parse_existing_assignments(path)
local success, write_error = write_mapping(path, subprojects, existing)

if not success then
    reaper.MB(
        "Could not write the mapping file:\n\n" .. tostring(write_error),
        "GJS-X FX scanner",
        0
    )
    return
end

reaper.MB(
    "FX scan complete.\n\n" ..
    "Scanned " .. tostring(#subprojects) .. " open subproject(s).\n" ..
    "For each subproject: first track + master track.\n\n" ..
    "Mapping file:\n" .. path .. "\n\n" ..
    "Use F1..F8 or B1..B8 after the desired parameters.",
    "GJS-X FX scanner",
    0
)

