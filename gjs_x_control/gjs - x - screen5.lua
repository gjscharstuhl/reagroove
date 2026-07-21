-- SCREEN5_LOAD_FAST_V11
-- ============================================================
-- Fix:
-- Laden gebeurt op on_release, niet op on_press.
-- Daardoor kan de core het pad niet na de projectwissel alsnog
-- naar OFF terugzetten.
-- ============================================================

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*[\\/])") or ""

local slot_manager = dofile(
    script_dir .. "gjs - x - slot_manager.lua"
)

local MODE_NOTE = 11
local HOME = os.getenv("HOME")
local JAMS_DIR = HOME and (HOME .. "/jams") or nil

local LOAD_EMPTY = { 0, 0, 10 }
local LOAD_FULL  = { 0, 0, 127 }

local SAVE_EMPTY = { 10, 3, 0 }
local SAVE_FULL  = { 127, 35, 0 }

local ACTIVE_RGB = { 127, 127, 127 }

local function slot_to_pad(slot)
    local zero = slot - 1

    return 8 - math.floor(zero / 8),
           (zero % 8) + 1
end

local function delayed_redraw(api)
    reaper.defer(function()
        api.redraw()
    end)
end

local function scan_existing_slots()
    local existing = {}

    if not JAMS_DIR then
        return existing
    end

    local index = 0

    while true do
        local name = reaper.EnumerateSubdirectories(
            JAMS_DIR,
            index
        )

        if not name then
            break
        end

        local slot = tonumber(
            name:match("^slot_(%d+)$")
        )

        if slot and slot >= 1 and slot <= 56 then
            existing[slot] = true
        end

        index = index + 1
    end

    return existing
end

local function show_error(message)
    reaper.ShowConsoleMsg(
        "Screen 5: " .. tostring(message) .. "\n"
    )
end

local function drawscreen5(api)
    local C = api.COLOR
    local state = api.get_screen_state(5)
    local save_mode = state.toggle[MODE_NOTE] == true
    local existing = scan_existing_slots()
    local active_slot = api.get_active_slot()

    local function rgb_for_slot(slot)
        if slot == active_slot then
            return ACTIVE_RGB
        end

        if save_mode then
            return existing[slot] and SAVE_FULL or SAVE_EMPTY
        end

        return existing[slot] and LOAD_FULL or LOAD_EMPTY
    end

    for slot = 1, 56 do
        local this_slot = slot
        local row, col = slot_to_pad(this_slot)

        api.drawpad(
            row,
            col,
            C.OFF,
            api.MODE_HIGHLIGHT,
            {
                active_color = C.WHITE,

                -- Alleen visuele highlight tijdens indrukken.
                on_press = function()
                end,

                -- Cruciale fix:
                -- start het laden pas nadat de release-afhandeling
                -- van drawpad is voltooid.
                on_release = function()
                    if save_mode then
                        local success, error_message =
                            slot_manager.save(this_slot)

                        if not success and error_message then
                            show_error(error_message)
                        end

                        delayed_redraw(api)
                        return
                    end

                    if not slot_manager.can_load(this_slot) then
                        delayed_redraw(api)
                        return
                    end

                    -- Core onthoudt onmiddellijk welk slot actief is.
                    -- Eerst redrawen, daarna pas de REAPER-projecten wisselen.
                    api.set_active_slot(this_slot)
                    api.redraw()

                    reaper.defer(function()
                        local success, error_message =
                            slot_manager.load(
                                this_slot
                            )

                        if not success and error_message then
                            show_error(error_message)
                            api.redraw()
                        end
                    end)
                end
            }
        )

        local rgb = rgb_for_slot(this_slot)

        api.send_pad_rgb(
            row,
            col,
            rgb[1],
            rgb[2],
            rgb[3]
        )
    end

    api.drawpad(
        1,
        1,
        C.YELLOW,
        api.MODE_TOGGLE,
        {
            active_color = C.ORANGE,

            on_release = function()
                delayed_redraw(api)
            end
        }
    )
end

return drawscreen5
