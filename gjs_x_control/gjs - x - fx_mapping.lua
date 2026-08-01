-- ============================================================
-- gjs - x - fx_mapping.lua
--
-- Reads fx_mapping.ini sections in natural visible-tab order:
--   [TabN.TrackM.FXK]
--   [TabN.Master.FXK]
--
-- load(path, tab_number) returns F1..F8 and B1..B8 mappings
-- belonging to the requested visible tab.
-- ============================================================

local M = {}

local function trim(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

local function valid_control(value)
    return type(value) == "string"
       and value:match("^[FB][1-8]$") ~= nil
end

local function parse_section(section_name)
    local tab_number, track_number, fx_number =
        section_name:match(
            "^Tab(%d+)%.Track(%d+)%.FX(%d+)$"
        )

    if tab_number and track_number and fx_number then
        return {
            tab_number = tonumber(tab_number),
            reaper_track_number = tonumber(track_number),
            is_master = false,
            fx_index = tonumber(fx_number) - 1
        }
    end

    tab_number, fx_number =
        section_name:match(
            "^Tab(%d+)%.Master%.FX(%d+)$"
        )

    if tab_number and fx_number then
        return {
            tab_number = tonumber(tab_number),
            reaper_track_number = nil,
            is_master = true,
            fx_index = tonumber(fx_number) - 1
        }
    end

    -- Backwards compatibility with old TrackN mappings.
    local old_track_number
    old_track_number, fx_number =
        section_name:match("^Track(%d+)%.FX(%d+)$")

    if old_track_number and fx_number then
        return {
            tab_number = tonumber(old_track_number),
            reaper_track_number = nil,
            is_master = false,
            fx_index = tonumber(fx_number) - 1,
            legacy_selected_track = true
        }
    end

    old_track_number, fx_number =
        section_name:match(
            "^Track(%d+)%.Master%.FX(%d+)$"
        )

    if old_track_number and fx_number then
        return {
            tab_number = tonumber(old_track_number),
            reaper_track_number = nil,
            is_master = true,
            fx_index = tonumber(fx_number) - 1
        }
    end

    return nil
end

function M.load(path, wanted_tab_number)
    local file, error_message = io.open(path, "r")

    if not file then
        return nil,
            error_message
            or "Mappingbestand kon niet worden geopend."
    end

    wanted_tab_number = tonumber(wanted_tab_number)

    local mappings = {}
    local current_section = nil
    local current_fx_name = nil
    local parameter_index = 0

    for raw_line in file:lines() do
        local line = trim(raw_line)

        if line == "" then
            -- Empty line.

        elseif line:sub(1, 1) == ";" then
            local fx_name =
                line:match("^;%s*FX:%s*(.-)%s*$")

            if fx_name then
                current_fx_name = fx_name
            end

        elseif line:match("^%[.-%]$") then
            local section_name =
                line:match("^%[(.-)%]$")

            current_section = parse_section(section_name)
            current_fx_name = nil
            parameter_index = 0

            if current_section then
                current_section.section_name = section_name
            end

        elseif current_section then
            local parameter_name, assigned_control =
                line:match("^(.-)=(.-)$")

            if parameter_name then
                parameter_name = trim(parameter_name)
                assigned_control =
                    trim(assigned_control):upper()

                local this_parameter_index =
                    parameter_index

                parameter_index = parameter_index + 1

                local tab_matches =
                    wanted_tab_number == nil
                    or current_section.tab_number
                        == wanted_tab_number

                if tab_matches
                and valid_control(assigned_control) then
                    mappings[assigned_control] = {
                        control = assigned_control,
                        tab_number =
                            current_section.tab_number,
                        reaper_track_number =
                            current_section.reaper_track_number,
                        is_master =
                            current_section.is_master,
                        legacy_selected_track =
                            current_section.legacy_selected_track,
                        fx_index =
                            current_section.fx_index,
                        fx_number =
                            current_section.fx_index + 1,
                        fx_name =
                            current_fx_name,
                        parameter_index =
                            this_parameter_index,
                        parameter_name =
                            parameter_name,
                        section_name =
                            current_section.section_name
                    }
                end
            end
        end
    end

    file:close()
    return mappings
end

local OUTPUT_FILENAME = "fx_mapping.ini"

function M.default_path()
    -- Always resolve beside visible Tab1 / REAPER project index 0.
    local _, project_file = reaper.EnumProjects(0, "")

    if not project_file or project_file == "" then
        return nil
    end

    local project_dir =
        project_file:match("^(.*)[/\\]")

    if not project_dir or project_dir == "" then
        return nil
    end

    local separator = package.config:sub(1, 1)
    return project_dir .. separator .. OUTPUT_FILENAME
end

return M
