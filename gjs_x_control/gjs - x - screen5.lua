-- SCREEN5_DRAWBLOCK_RGB_V12
-- ============================================================
-- Rijen 8 t/m 2: 56 jam-slots.
-- Linksboven = slot 1, rechtsonder = slot 56.
--
-- Load mode:
--   leeg     = donkerblauw
--   bestaand = felblauw
--
-- Save mode:
--   leeg     = donkeroranje
--   bestaand = feloranje
--
-- Actief geladen slot = wit.
-- ============================================================

local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.*[\\/])") or ""

local slot_manager = dofile(
    script_dir .. "gjs - x - slot_manager.lua"
)

local clear = dofile(
    script_dir .. "gjs - x - clear.lua"
)


local MODE_NOTE = 11

local HOME = os.getenv("HOME") or os.getenv("USERPROFILE")
if not HOME then
    local drive = os.getenv("HOMEDRIVE")
    local path = os.getenv("HOMEPATH")
    if drive and path then HOME = drive .. path end
end
local REABOX_DIR = HOME and (HOME .. "/ReaBox") or nil

local LOAD_EMPTY = { 0, 0, 10 }
local LOAD_FULL  = { 0, 0, 127 }

local SAVE_EMPTY = { 10, 3, 0 }
local SAVE_FULL  = { 127, 35, 0 }

local ACTIVE_RGB = { 127, 127, 127 }

------------------------------------------------------------
-- Pad/slot conversion
------------------------------------------------------------

local function pad_to_slot(row, col)
    return ((8 - row) * 8) + col
end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function delayed_redraw(api)
    reaper.defer(function()
        api.redraw()
    end)
end

local function scan_existing_slots()
    local existing = {}

    if not REABOX_DIR then
        return existing
    end

    local index = 0

    while true do
        local name = reaper.EnumerateSubdirectories(
            REABOX_DIR,
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

------------------------------------------------------------
-- Screen
------------------------------------------------------------

local function drawscreen5(api)
    local C = api.COLOR
    local state = api.get_screen_state(5)

    local save_mode =
        state.toggle[MODE_NOTE] == true

    local existing =
        scan_existing_slots()

    local active_slot =
        api.get_active_slot()

    --------------------------------------------------------
    -- Slot background
    --------------------------------------------------------

    local function slot_background_rgb(row, col)
        local slot = pad_to_slot(row, col)

        if slot == active_slot then
            return ACTIVE_RGB
        end

        if save_mode then
            return existing[slot]
                and SAVE_FULL
                or SAVE_EMPTY
        end

        return existing[slot]
            and LOAD_FULL
            or LOAD_EMPTY
    end

    --------------------------------------------------------
    -- Slot action
    --------------------------------------------------------

    local function handle_slot_release(pad)
        local slot =
            pad_to_slot(pad.row, pad.col)

        if save_mode then
            local success, error_message =
                slot_manager.save(slot)

            if not success and error_message then
                show_error(error_message)
            end

            delayed_redraw(api)
            return
        end

        if not slot_manager.can_load(slot) then
            delayed_redraw(api)
            return
        end

        -- Meteen onthouden welk slot actief wordt.
        api.set_active_slot(slot)

        -- Eerst de nieuwe actieve status tekenen.
        -- Daarna pas de REAPER-projecten wisselen.
        reaper.defer(function()
            api.redraw()

            reaper.defer(function()
                local success, error_message =
                    slot_manager.load(slot)

                if not success and error_message then
                    show_error(error_message)
                end

                api.redraw()
            end)
        end)
    end

    --------------------------------------------------------
    -- Slots 1 t/m 56
    --------------------------------------------------------

    api.drawblock(
        8,
        1,
        2,
        8,
        C.OFF,
        api.MODE_HIGHLIGHT,
        {
            background_rgb = slot_background_rgb,
            active_rgb = ACTIVE_RGB,

            -- De actie gebeurt pas bij loslaten.
            on_release = handle_slot_release
        }
    )

    --------------------------------------------------------
    -- Load/save toggle
    --------------------------------------------------------

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

    --------------------------------------------------------
    -- New project (pad 12, next to load/save)
    --------------------------------------------------------

    api.drawpad(
        1,
        2,
        C.GREEN,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,

            on_release = function()
                local home = os.getenv("HOME")
                    or os.getenv("USERPROFILE")
                    or ((os.getenv("HOMEDRIVE") or "") .. (os.getenv("HOMEPATH") or ""))

                if not home or home == "" then
                    show_error("HOME directory niet gevonden.")
                    return
                end

                home = home:gsub("\\", "/")
                local default_dir = home .. "/ReaBox/default"
                local rpl_file = default_dir .. "/Media/projlist.RPL"

                api.set_active_slot(nil)
                api.redraw()

                local success, error_message = slot_manager.load_rpl(
                    rpl_file,
                    default_dir,
                    function()
                        clear.clear_all_regions_all_projects({
                            items = true,
                            fx = true,
                            track_mode = "all"
                        })
                        api.redraw()
                    end
                )

                if not success and error_message then
                    show_error(error_message)
                end
            end
        }
    )
end

return drawscreen5
