-- FX_MAPPING_ACTIVE_TRACK_V5
-- ============================================================
-- gjs - x - fx_mapping.lua
--
-- Leest gjs_page3_fx_mapping.ini.
-- load(path, track_number) geeft alleen F1..F8 mappings terug
-- die bij de gekozen TrackN-secties horen.
-- B1..B8 worden nog wel herkend voor compatibiliteit, maar
-- Page 3 gebruikt ze niet.
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
    local track_number, fx_number =
        section_name:match("^Track(%d+)%.FX(%d+)$")

    if track_number and fx_number then
        return {
            track_number = tonumber(track_number),
            is_master = false,
            fx_index = tonumber(fx_number) - 1
        }
    end

    track_number, fx_number =
        section_name:match("^Track(%d+)%.Master%.FX(%d+)$")

    if track_number and fx_number then
        return {
            track_number = tonumber(track_number),
            is_master = true,
            fx_index = tonumber(fx_number) - 1
        }
    end

    return nil
end

function M.load(path, wanted_track_number)
    local file, error_message = io.open(path, "r")
    if not file then
        return nil, error_message or "Mappingbestand kon niet worden geopend."
    end

    wanted_track_number = tonumber(wanted_track_number)

    local mappings = {}
    local current_section = nil
    local current_fx_name = nil
    local parameter_index = 0

    for raw_line in file:lines() do
        local line = trim(raw_line)

        if line == "" then
            -- lege regel

        elseif line:sub(1, 1) == ";" then
            local fx_name = line:match("^;%s*FX:%s*(.-)%s*$")
            if fx_name then
                current_fx_name = fx_name
            end

        elseif line:match("^%[.-%]$") then
            local section_name = line:match("^%[(.-)%]$")
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
                assigned_control = trim(assigned_control):upper()

                local this_parameter_index = parameter_index
                parameter_index = parameter_index + 1

                local track_matches =
                    wanted_track_number == nil
                    or current_section.track_number == wanted_track_number

                if track_matches and valid_control(assigned_control) then
                    mappings[assigned_control] = {
                        control = assigned_control,
                        track_number = current_section.track_number,
                        is_master = current_section.is_master,
                        fx_index = current_section.fx_index,
                        fx_number = current_section.fx_index + 1,
                        fx_name = current_fx_name,
                        parameter_index = this_parameter_index,
                        parameter_name = parameter_name,
                        section_name = current_section.section_name
                    }
                end
            end
        end
    end

    file:close()
    return mappings
end

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*[\\/])") or ""

function M.default_path()
    return script_dir .. "gjs_page3_fx_mapping.ini"
end

return M
