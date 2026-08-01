-- ============================================================
-- GJS-X - Scan FX parameters on all tracks for Reagroove tracks 1..8
--
-- Run this script from the main project tab.
-- For every other open project tab, it scans:
--   1. every normal REAPER track
--   2. the project master track
--
-- Normal tracks use TrackN.TrackM.FXK.
-- Master FX use TrackN.Master.FXK.
--
-- Enter F1..F8 or B1..B8 after the desired parameters.
-- Existing assignments are preserved when scanning again.
-- ============================================================

local MAX_SUBPROJECTS = 8
local OUTPUT_FILENAME = "fx_mapping.ini"

-- User-facing tab labels:
-- internal slot 8 is the central mixer in REAPER project 0,
-- so it appears as Tab1. Internal slots 1..7 appear as Tab2..Tab8.
local TAB_LABELS = {
    [1] = "Tab2",
    [2] = "Tab3",
    [3] = "Tab4",
    [4] = "Tab5",
    [5] = "Tab6",
    [6] = "Tab7",
    [7] = "Tab8",
    [8] = "Tab1"
}

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

local function collect_mapping_projects()
    local projects = {}

    -- Reagroove tracks 1..7 use project tabs 1..7.
    for slot = 1, 7 do
        local project, project_file = reaper.EnumProjects(slot, "")

        if project then
            projects[slot] = {
                project = project,
                path = project_file or ""
            }
        end
    end

    -- Reagroove track 8 is now the central mixer in project 0.
    local main_project, main_project_file = reaper.EnumProjects(0, "")

    if main_project then
        projects[8] = {
            project = main_project,
            path = main_project_file or ""
        }
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

            local label = TAB_LABELS[slot] or ("Tab" .. tostring(slot))
            if label == "Tab1" then
                label = "Tab1 (Main Project)"
            end

            file:write(string.format(
                "; %s - %s\n",
                label,
                clean_label(project_name)
            ))
            file:write("; ------------------------------------------------------------\n\n")

            -- Scan every normal REAPER track in this project.
            local track_count = reaper.CountTracks(project)

            if track_count == 0 then
                file:write("; No normal tracks found.\n\n")
            else
                for track_index = 0, track_count - 1 do
                    local track = reaper.GetTrack(project, track_index)
                    local track_name = get_track_name(track)
                    local track_number = track_index + 1

                    file:write(string.format(
                        "; TRACK %d: %s\n\n",
                        track_number,
                        track_name ~= "" and track_name or "Unnamed track"
                    ))

                    write_fx_sections(
                        file,
                        track,
                        string.format(
                            "%s.Track%d",
                            TAB_LABELS[slot] or ("Tab" .. tostring(slot)),
                            track_number
                        ),
                        existing
                    )
                end
            end

            -- Master FX in the same project.
            local master_track = reaper.GetMasterTrack(project)
            file:write("; MASTER TRACK\n\n")
            write_fx_sections(
                file,
                master_track,
                (TAB_LABELS[slot] or ("Tab" .. tostring(slot))) .. ".Master",
                existing
            )
        end
    end

    file:close()
    return true
end

local subprojects = collect_mapping_projects()

local scanned_count = 0
for slot = 1, MAX_SUBPROJECTS do
    if subprojects[slot] then
        scanned_count = scanned_count + 1
    end
end

if scanned_count == 0 then
    reaper.MB(
        "No Reagroove project tabs were found.",
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
    "Scanned " .. tostring(scanned_count) .. " Reagroove project(s).\n" ..
    "For each project: all normal tracks + master track.\n\n" ..
    "Mapping file:\n" .. path .. "\n\n" ..
    "Use F1..F8 or B1..B8 after the desired parameters.",
    "GJS-X FX scanner",
    0
)


