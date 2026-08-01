-- ============================================================
-- GJS-X - Scan FX parameters in visible project tabs 1..8
--
-- Natural tab flow:
--   Tab1 = REAPER project index 0
--   Tab2 = REAPER project index 1
--   ...
--   Tab8 = REAPER project index 7
--
-- For every open tab it scans:
--   1. every normal REAPER track
--   2. the project master track
--
-- Normal track sections:
--   [TabN.TrackM.FXK]
--
-- Master track sections:
--   [TabN.Master.FXK]
--
-- Enter F1..F8 or B1..B8 after desired parameters.
-- Existing assignments are preserved when scanning again.
-- ============================================================

local MAX_TABS = 8
local OUTPUT_FILENAME = "fx_mapping.ini"

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

local function dirname(path)
    return (path or ""):match("^(.*)[/\\]")
end

local function get_track_name(track)
    local _, name = reaper.GetTrackName(track)
    return clean_label(name)
end

local function output_path()
    -- Always store beside visible Tab1 / REAPER project index 0.
    local _, project_file = reaper.EnumProjects(0, "")
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
        file:write("; FX: " ..
            (fx_name ~= "" and fx_name or "Unnamed FX") ..
            "\n")

        local parameter_count =
            reaper.TrackFX_GetNumParams(track, fx_index)

        local used_keys = {}

        if parameter_count == 0 then
            file:write("; No parameters found.\n")
        end

        for parameter_index = 0, parameter_count - 1 do
            local _, parameter_name =
                reaper.TrackFX_GetParamName(
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

            if existing[section]
            and existing[section][key] then
                old_value = existing[section][key]
            end

            file:write(key .. "=" .. old_value .. "\n")
        end

        file:write("\n")
    end
end

local function write_mapping(path, existing)
    local file, error_message = io.open(path, "w")

    if not file then
        return false, error_message, 0
    end

    file:write("; ============================================================\n")
    file:write("; GJS-X plugin mapping\n")
    file:write("; Natural visible-tab order: Tab1 through Tab8\n")
    file:write("; F1..F8 = vertical faders\n")
    file:write("; B1..B8 = horizontal controls\n")
    file:write("; Leave unused parameters empty.\n")
    file:write("; Running the scanner again preserves assignments.\n")
    file:write("; ============================================================\n\n")

    local scanned_count = 0

    for project_index = 0, MAX_TABS - 1 do
        local tab_number = project_index + 1
        local project, project_file =
            reaper.EnumProjects(project_index, "")

        file:write("; ------------------------------------------------------------\n")

        if not project then
            file:write(string.format(
                "; Tab%d - not open\n",
                tab_number
            ))
            file:write("; ------------------------------------------------------------\n\n")
        else
            scanned_count = scanned_count + 1

            local project_name =
                basename_without_extension(project_file)

            if project_name == "" then
                project_name = "Unsaved project"
            end

            local heading =
                tab_number == 1
                and "Tab1 (Main Project)"
                or ("Tab" .. tostring(tab_number))

            file:write(string.format(
                "; %s - %s\n",
                heading,
                clean_label(project_name)
            ))
            file:write("; ------------------------------------------------------------\n\n")

            local track_count = reaper.CountTracks(project)

            if track_count == 0 then
                file:write("; No normal tracks found.\n\n")
            else
                for track_index = 0, track_count - 1 do
                    local track =
                        reaper.GetTrack(project, track_index)

                    local track_number = track_index + 1
                    local track_name = get_track_name(track)

                    file:write(string.format(
                        "; TRACK %d: %s\n\n",
                        track_number,
                        track_name ~= ""
                            and track_name
                            or "Unnamed track"
                    ))

                    write_fx_sections(
                        file,
                        track,
                        string.format(
                            "Tab%d.Track%d",
                            tab_number,
                            track_number
                        ),
                        existing
                    )
                end
            end

            local master_track =
                reaper.GetMasterTrack(project)

            file:write("; MASTER TRACK\n\n")

            write_fx_sections(
                file,
                master_track,
                string.format("Tab%d.Master", tab_number),
                existing
            )
        end
    end

    file:close()
    return true, nil, scanned_count
end

local path = output_path()
local existing = parse_existing_assignments(path)

local success, write_error, scanned_count =
    write_mapping(path, existing)

if not success then
    reaper.MB(
        "Could not write the mapping file:\n\n" ..
        tostring(write_error),
        "GJS-X FX scanner",
        0
    )
    return
end

reaper.MB(
    "FX scan complete.\n\n" ..
    "Scanned " .. tostring(scanned_count) ..
    " visible project tab(s).\n" ..
    "For each tab: all normal tracks + master track.\n\n" ..
    "Mapping file:\n" .. path .. "\n\n" ..
    "Use F1..F8 or B1..B8 after desired parameters.",
    "GJS-X FX scanner",
    0
)
