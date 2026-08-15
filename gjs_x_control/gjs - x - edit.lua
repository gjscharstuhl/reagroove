-- ============================================================
-- gjs - x - edit.lua
-- Version 07 - subproject track selector on action pad 5
-- ============================================================

local source = debug.getinfo(1, "S").source
local script_path = source:match("^@(.+)$") or ""
local script_dir = script_path:match("^(.*[/\\])") or ""

local resize = dofile(script_dir .. "gjs - x - resize.lua")
local clear = dofile(script_dir .. "gjs - x - clear.lua")
local merge = dofile(script_dir .. "gjs - x - merge.lua")
local time_signature = dofile(
    script_dir .. "gjs - x - time_signature.lua"
)
local subproject_track = dofile(
    script_dir .. "gjs - x - subproject_track.lua"
)
local save_and_quit = dofile(
    script_dir .. "gjs - x - save_and_quit.lua"
)
local sequencer = dofile(
    script_dir .. "gjs - x - sequencer_engine.lua"
)
local pattern_copy = dofile(
    script_dir .. "gjs - x - pattern_copy.lua"
)
local preset_selector = dofile(
    script_dir .. "gjs - x - preset_selector.lua"
)
local pattern_slots = dofile(
    script_dir .. "gjs - x - pattern_slots.lua"
)

local SCOPE_SELECTED_TRACK = 1
local SCOPE_ALL_TRACKS = 2
local SCOPE_ALL_REGIONS = 3

local MERGE_SELECTED_PROJECT = 1
local MERGE_ALL_PROJECTS = 2

local ACTION_RESIZE_COL = 1
local ACTION_CLEAR_COL = 2
local ACTION_MERGE_COL = 3
local ACTION_TIME_SIGNATURE_COL = 4
local ACTION_TRACK_SELECT_COL = 5
local ACTION_PATTERN_COPY_COL = 6
local ACTION_PRESET_SELECTOR_COL = 7
local ACTION_SAVE_QUIT_COL = 8
local ACTION_PATTERN_SLOTS_ROW = 2
local ACTION_PATTERN_SLOTS_COL = 1

local selected_bars = 1
local selected_track = nil
local selected_region = nil
local last_main_entry_serial = nil
local selected_scope = SCOPE_SELECTED_TRACK

local resize_mode = false
local time_signature_mode = false
local track_select_mode = false
local clear_mode = false
local clear_items = false
local clear_fx = false
local clear_track_mode = 1 -- 1 = armed, 2 = all top-level tracks

local pattern_copy_mode = false
local copy_from_region = nil
local copy_to_region = nil
local copy_track_mode = 1 -- 1 = armed/selected tracks, 2 = all tracks
local preset_selector_mode = false
local pattern_slots_mode = false
local pattern_slot_selected = 1
local pattern_slot_save_mode = false
local pattern_preview_session = nil
local pattern_audio_stretch = true -- pad 14: audio follows region length by default

local merge_mode = false
local merge_scope = MERGE_SELECTED_PROJECT
local merge_sequence = {}
local MAX_MERGE_STEPS = 16

local function clamp(value, minimum, maximum, fallback)
    value = tonumber(value)

    if not value then
        return fallback
    end

    value = math.floor(value)

    if value < minimum then
        return minimum
    elseif value > maximum then
        return maximum
    end

    return value
end

local function sync_main_selection_on_entry(api)
    local entry = api and api._screen0_edit_entry or nil

    if entry and entry.serial ~= last_main_entry_serial then
        selected_track = clamp(entry.track, 1, 8, 1)
        selected_region = clamp(entry.pattern or entry.region, 1, 8, 1)
        last_main_entry_serial = entry.serial
        return
    end

    -- Fallback for opening Edit before Main has supplied an entry snapshot.
    if not selected_track then
        selected_track = clamp(
            reaper.GetExtState("GJS_MULTI", "ActiveTrack"),
            1, 8, 1
        )
    end

    if not selected_region then
        selected_region = clamp(
            reaper.GetExtState("GJS_MULTI", "Region"),
            1, 8, 1
        )
    end
end

local function execute_resize()
    if selected_scope == SCOPE_SELECTED_TRACK then
        return resize.resize_selected_region_selected_project(
            selected_track, selected_region, selected_bars
        )
    elseif selected_scope == SCOPE_ALL_TRACKS then
        return resize.resize_selected_region_all_projects(
            selected_region, selected_bars
        )
    elseif selected_scope == SCOPE_ALL_REGIONS then
        return resize.resize_all_regions_all_projects(selected_bars)
    end

    return false
end

local function execute_clear()
    if not clear_items and not clear_fx then
        return false
    end

    local options = {
        items = clear_items,
        fx = clear_fx,
        track_mode =
            clear_track_mode == 2 and "all" or "armed"
    }

    if selected_scope == SCOPE_SELECTED_TRACK then
        clear.clear_selected_region_selected_project(
            selected_track,
            selected_region,
            options
        )
        return true
    elseif selected_scope == SCOPE_ALL_TRACKS then
        clear.clear_selected_region_all_projects(
            selected_region,
            options
        )
        return true
    elseif selected_scope == SCOPE_ALL_REGIONS then
        clear.clear_all_regions_all_projects(options)
        return true
    end

    return false
end

local function draw_resize_mode(api, C)
    -- Bars: rows 8-7, same selector as the main edit page.
    api.drawstrip(8, 1, 8, C.PURPLE, api.MODE_RADIO, {
        group = "edit_resize_value_1_16",
        selected_row = selected_bars <= 8 and 8 or 7,
        selected_col = selected_bars <= 8 and selected_bars or selected_bars - 8,
        active_color = C.WHITE,
        on_press = function(pad)
            selected_bars = pad.col
            api.redraw()
        end
    })
    api.drawstrip(7, 1, 8, C.PURPLE, api.MODE_RADIO, {
        group = "edit_resize_value_1_16",
        selected_row = selected_bars <= 8 and 8 or 7,
        selected_col = selected_bars <= 8 and selected_bars or selected_bars - 8,
        active_color = C.WHITE,
        on_press = function(pad)
            selected_bars = 8 + pad.col
            api.redraw()
        end
    })

    api.drawstrip(6, 1, 8, C.LIGHT_BLUE, api.MODE_RADIO, {
        group = "edit_resize_region",
        selected_col = selected_region,
        active_color = C.WHITE,
        on_press = function(pad)
            selected_region = pad.col
            api.redraw()
        end
    })

    api.drawstrip(4, 6, 8, C.GREEN, api.MODE_RADIO, {
        group = "edit_resize_scope",
        selected_col = 5 + selected_scope,
        active_color = C.WHITE,
        on_press = function(pad)
            selected_scope = pad.col - 5
            api.redraw()
        end
    })

    api.drawstrip(2, 1, 8, C.ORANGE, api.MODE_RADIO, {
        group = "edit_resize_track",
        selected_col = selected_track,
        active_color = C.WHITE,
        on_press = function(pad)
            selected_track = pad.col
            api.redraw()
        end
    })

    -- Universal edit controls: 11 confirm, 12 cancel.
    api.drawpad(1, 1, C.GREEN, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function()
            execute_resize()
            resize_mode = false
            api.redraw()
        end
    })
    api.drawpad(1, 2, C.RED, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function()
            resize_mode = false
            api.redraw()
        end
    })
end

local function draw_clear_mode(api, C)
    local off_items = { 30, 20, 0 }
    local off_fx = { 24, 0, 30 }

    -- Items toggle.
    api.drawpad(
        8,
        1,
        clear_items and C.YELLOW or off_items,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            on_press = function()
                clear_items = not clear_items
                api.redraw()
            end
        }
    )

    -- FX/automation toggle.
    api.drawpad(
        8,
        2,
        clear_fx and C.PURPLE or off_fx,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            on_press = function()
                clear_fx = not clear_fx
                api.redraw()
            end
        }
    )

    -- Keep scope, region and project visible/editable in this subscreen.
    api.drawstrip(
        6, 1, 8,
        C.LIGHT_BLUE,
        api.MODE_RADIO,
        {
            group = "edit_clear_region",
            selected_row = 6,
            selected_col = selected_region,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_region = pad.col
                api.redraw()
            end
        }
    )

    -- Track target: armed tracks or all top-level tracks.
    api.drawstrip(
        4, 1, 2,
        C.GREEN,
        api.MODE_RADIO,
        {
            group = "edit_clear_track_mode",
            selected_row = 4,
            selected_col = clear_track_mode,
            active_color = C.WHITE,

            on_press = function(pad)
                clear_track_mode = pad.col
                api.redraw()
            end
        }
    )

    api.drawstrip(
        4, 6, 8,
        C.GREEN,
        api.MODE_RADIO,
        {
            group = "edit_clear_scope",
            selected_col = 5 + selected_scope,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_scope = pad.col - 5
                api.redraw()
            end
        }
    )

    api.drawstrip(
        2, 1, 8,
        C.ORANGE,
        api.MODE_RADIO,
        {
            group = "edit_clear_track",
            selected_col = selected_track,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_track = pad.col
                api.redraw()
            end
        }
    )

    -- Universal edit controls: 11 confirm, 12 cancel.
    api.drawpad(
        1, 1,
        C.GREEN,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            on_press = function()
                if execute_clear() then
                    clear_mode = false
                end
                api.redraw()
            end
        }
    )

    api.drawpad(
        1, 2,
        C.RED,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            on_press = function()
                clear_mode = false
                api.redraw()
            end
        }
    )
end


local function draw_pattern_copy_mode(api, C)
    local from_dark = { 22, 0, 30 }
    local to_dark = { 0, 18, 32 }

    -- Row 8: source pattern (FROM).
    for col = 1, 8 do
        api.drawpad(8, col, copy_from_region == col and C.WHITE or C.PURPLE, api.MODE_HIGHLIGHT, {
            active_color = C.WHITE,
            on_press = function(pad)
                copy_from_region = pad.col
                api.redraw()
            end
        })
    end

    -- Row 7: target pattern (TO).
    for col = 1, 8 do
        api.drawpad(7, col, copy_to_region == col and C.WHITE or C.LIGHT_BLUE, api.MODE_HIGHLIGHT, {
            active_color = C.WHITE,
            on_press = function(pad)
                copy_to_region = pad.col
                api.redraw()
            end
        })
    end

    -- Same track-scope choice as Clear: armed/selected tracks or all tracks.
    api.drawstrip(4, 1, 2, C.GREEN, api.MODE_RADIO, {
        group = "edit_copy_track_mode",
        selected_row = 4,
        selected_col = copy_track_mode,
        active_color = C.WHITE,
        on_press = function(pad)
            copy_track_mode = pad.col
            api.redraw()
        end
    })

    -- Keep the selected subproject visible on row 2.
    api.drawstrip(2, 1, 8, C.ORANGE, api.MODE_RADIO, {
        group = "edit_copy_track",
        selected_col = selected_track,
        active_color = C.WHITE,
        on_press = function(pad)
            selected_track = pad.col
            api.redraw()
        end
    })

    -- Universal edit controls: 11 confirm, 12 cancel.
    api.drawpad(1, 1, C.GREEN, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function()
            if copy_from_region and copy_to_region then
                local ok, err = pattern_copy.copy(
                    selected_track,
                    copy_from_region,
                    copy_to_region,
                    { track_mode = copy_track_mode == 2 and "all" or "armed" }
                )
                if ok then
                    pattern_copy_mode = false
                    copy_from_region = nil
                    copy_to_region = nil
                elseif err then
                    reaper.ShowConsoleMsg("Pattern copy failed: " .. tostring(err) .. "\\n")
                end
            end
            api.redraw()
        end
    })

    api.drawpad(1, 2, C.RED, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function()
            pattern_copy_mode = false
            copy_from_region = nil
            copy_to_region = nil
            api.redraw()
        end
    })
end

local function execute_merge()
    if #merge_sequence == 0 then
        return false
    end

    local ok, error_message

    if merge_scope == MERGE_SELECTED_PROJECT then
        ok, error_message = merge.merge_selected_project(
            selected_track,
            merge_sequence,
            selected_region
        )
    else
        ok, error_message = merge.merge_all_projects(
            merge_sequence,
            selected_region
        )
    end

    if not ok and error_message then
        reaper.ShowConsoleMsg(
            "Pattern merge failed: " .. tostring(error_message) .. "\n"
        )
    end

    return ok
end

local function region_colour(C, region_number)
    local colours = {
        C.RED,
        C.ORANGE,
        C.YELLOW,
        C.GREEN,
        C.LIGHT_BLUE,
        C.BLUE,
        C.PURPLE,
        C.MAGENTA
    }

    return colours[region_number] or C.WHITE
end

local function append_merge_region(region_number)
    if #merge_sequence >= MAX_MERGE_STEPS then
        return
    end

    merge_sequence[#merge_sequence + 1] = region_number
end

local function draw_merge_sequence(api, C)
    -- Top two rows are display-only.
    for row = 8, 7, -1 do
        for col = 1, 8 do
            local sequence_index = (8 - row) * 8 + col
            local source_region = merge_sequence[sequence_index]
            local colour = source_region
                and region_colour(C, source_region)
                or C.OFF

            api.drawpad(row, col, colour, api.MODE_NONE)
        end
    end
end

local function draw_merge_source_selection(api, C)
    -- Rows 6 and 5 are source-region selectors.
    for row = 6, 5, -1 do
        for col = 1, 8 do
            api.drawpad(
                row,
                col,
                region_colour(C, col),
                api.MODE_HIGHLIGHT,
                {
                    active_color = C.WHITE,
                    on_press = function(pad)
                        append_merge_region(pad.col)
                        api.redraw()
                    end
                }
            )
        end
    end
end

local function draw_merge_mode(api, C)
    draw_merge_sequence(api, C)
    draw_merge_source_selection(api, C)

    api.drawstrip(
        4, 1, 8,
        C.LIGHT_BLUE,
        api.MODE_RADIO,
        {
            group = "edit_merge_target_region",
            selected_row = 4,
            selected_col = selected_region,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_region = pad.col
                api.redraw()
            end
        }
    )

    api.drawstrip(
        3, 1, 2,
        C.GREEN,
        api.MODE_RADIO,
        {
            group = "edit_merge_scope",
            selected_row = 3,
            selected_col = merge_scope,
            active_color = C.WHITE,
            on_press = function(pad)
                merge_scope = pad.col
                api.redraw()
            end
        }
    )

    api.drawstrip(
        2, 1, 8,
        C.ORANGE,
        api.MODE_RADIO,
        {
            group = "edit_track",
            selected_row = 2,
            selected_col = selected_track,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_track = pad.col
                api.redraw()
            end
        }
    )

    -- Universal edit controls: 11 confirm, 12 cancel.
    api.drawpad(1, 1, C.GREEN, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function()
            if execute_merge() then
                merge_mode = false
                merge_sequence = {}
            end
            api.redraw()
        end
    })

    api.drawpad(1, 2, C.RED, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function()
            merge_mode = false
            merge_sequence = {}
            api.redraw()
        end
    })

    -- Pad 13 removes the last source pattern while building the merge.
    api.drawpad(1, 3, C.ORANGE, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function()
            merge_sequence[#merge_sequence] = nil
            api.redraw()
        end
    })
end

local function draw_pattern_slots_mode(api, C)
    local LOAD_EMPTY = { 0, 0, 10 }
    local LOAD_FULL = { 0, 0, 70 }
    local SAVE_EMPTY = { 10, 3, 0 }
    local SAVE_FULL = { 70, 22, 0 }
    local existing = pattern_slots.scan_existing(selected_track)

    local function pad_to_slot(row, col)
        return ((8 - row) * 8) + col
    end

    local function slot_background(row, col)
        local slot = pad_to_slot(row, col)
        if slot == pattern_slot_selected then
            return C.WHITE
        end
        if pattern_slot_save_mode then
            return existing[slot] and SAVE_FULL or SAVE_EMPTY
        end
        return existing[slot] and LOAD_FULL or LOAD_EMPTY
    end

    -- 56 pattern slots: rows 8 through 2.
    api.drawblock(8, 1, 2, 8, C.OFF, api.MODE_HIGHLIGHT, {
        background_rgb = slot_background,
        active_color = C.WHITE,
        on_press = function(pad)
            pattern_slot_selected = pad_to_slot(pad.row, pad.col)

            if not pattern_slot_save_mode and existing[pattern_slot_selected] then
                if not pattern_preview_session then
                    local session, begin_err = pattern_slots.begin_preview(
                        selected_track,
                        selected_region
                    )
                    pattern_preview_session = session
                    if not session and begin_err then
                        reaper.ShowConsoleMsg(
                            "Pattern preview: " .. tostring(begin_err) .. "\n"
                        )
                    end
                end

                if pattern_preview_session then
                    local ok, err = pattern_slots.preview_load(
                        pattern_preview_session,
                        pattern_slot_selected,
                        pattern_audio_stretch
                    )
                    if not ok and err then
                        reaper.ShowConsoleMsg(
                            "Pattern preview: " .. tostring(err) .. "\n"
                        )
                    end
                end
            end

            api.redraw()
        end,

        -- The press redraws this block with the new selected slot.
        -- Prevent MODE_HIGHLIGHT release from restoring the old LED colour.
        on_release = function()
            return true
        end
    })

    -- 11 confirm, 12 exit, 13 load/save toggle.
    api.drawpad(1, 1, C.GREEN, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function()
            local ok, err
            if pattern_slot_save_mode then
                ok, err = pattern_slots.save(
                    pattern_slot_selected,
                    selected_track,
                    selected_region
                )
            else
                -- Load mode is already live-previewed by pressing a slot pad.
                -- Confirm simply accepts the currently previewed project state.
                ok, err = pattern_slots.confirm_preview(pattern_preview_session)
                pattern_preview_session = nil
            end

            if not ok and err then
                reaper.ShowConsoleMsg("Pattern slots: " .. tostring(err) .. "\n")
            elseif ok then
                pattern_slots_mode = false
            end
            api.redraw()
        end
    })

    api.drawpad(1, 2, C.RED, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function()
            if pattern_preview_session then
                local ok, err = pattern_slots.cancel_preview(pattern_preview_session)
                pattern_preview_session = nil
                if not ok and err then
                    reaper.ShowConsoleMsg(
                        "Pattern preview cancel: " .. tostring(err) .. "\n"
                    )
                end
            end
            pattern_slots_mode = false
            api.redraw()
        end
    })

    api.drawpad(
        1, 3,
        pattern_slot_save_mode and C.ORANGE or C.YELLOW,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            on_press = function()
                if not pattern_slot_save_mode then
                    -- Leaving load-preview mode for save: restore the original
                    -- state first, so a preview can never accidentally be saved.
                    if pattern_preview_session then
                        local ok, err = pattern_slots.cancel_preview(pattern_preview_session)
                        pattern_preview_session = nil
                        if not ok and err then
                            reaper.ShowConsoleMsg(
                                "Pattern preview: " .. tostring(err) .. "\n"
                            )
                        end
                    end
                    pattern_slot_save_mode = true
                else
                    pattern_slot_save_mode = false
                    local session, err = pattern_slots.begin_preview(
                        selected_track,
                        selected_region
                    )
                    pattern_preview_session = session
                    if not session and err then
                        reaper.ShowConsoleMsg(
                            "Pattern preview: " .. tostring(err) .. "\n"
                        )
                    end
                end
                api.redraw()
            end,

            -- Keep the newly redrawn load/save state visible on release.
            on_release = function()
                return true
            end
        }
    )


    -- 14 audio load behaviour toggle. BLUE (default): stretch audio to the
    -- existing region. PURPLE: resize the region to the sample length.
    -- Use HIGHLIGHT so the core actually dispatches on_press; on_release=true
    -- prevents the old pad instance from restoring its pre-redraw colour.
    api.drawpad(1, 4, pattern_audio_stretch and C.BLUE or C.PURPLE, api.MODE_HIGHLIGHT, {
        active_color = C.WHITE,
        on_press = function()
            pattern_audio_stretch = not pattern_audio_stretch

            -- While auditioning, immediately re-apply the selected slot from
            -- the original preview snapshot so the difference is audible.
            if not pattern_slot_save_mode
                and pattern_preview_session
                and existing[pattern_slot_selected] then
                local ok, err = pattern_slots.preview_load(
                    pattern_preview_session,
                    pattern_slot_selected,
                    pattern_audio_stretch
                )
                if not ok and err then
                    reaper.ShowConsoleMsg(
                        "Pattern stretch: " .. tostring(err) .. "\n"
                    )
                end
            end
            api.redraw()
        end,

        -- The press redraws pad 14 immediately in its new blue/purple state.
        -- Do not let MODE_HIGHLIGHT release restore the old colour afterwards.
        on_release = function()
            return true
        end
    })
end

return function(api, navigation)
    local C = api.COLOR

    sync_main_selection_on_entry(api)

    if api.set_screen0_main_active then
        api.set_screen0_main_active(false)
    end

    if api.set_jsfx_loop_overview_active then
        api.set_jsfx_loop_overview_active(false)
    end

    -- Main and Edit share screen 0. Explicitly disable the mainscreen
    -- JSFX overlay here, otherwise it keeps drawing over the Edit layout.
    if sequencer and type(sequencer.disable_display) == "function" then
        sequencer.disable_display(2)
    end

    if api.set_navigation then
        api.set_navigation(
            navigation and navigation.open_main or nil,
            nil
        )
    end

    api.drawblock(8, 1, 1, 8, C.OFF, api.MODE_NONE)

    if resize_mode then
        draw_resize_mode(api, C)
        return
    end

    if time_signature_mode then
        time_signature.draw(
            api,
            C,
            function()
                time_signature_mode = false
            end
        )
        return
    end

    if track_select_mode then
        subproject_track.draw(
            api, C, selected_track,
            function() track_select_mode = false end
        )
        return
    end

    if clear_mode then
        draw_clear_mode(api, C)
        return
    end

    if merge_mode then
        draw_merge_mode(api, C)
        return
    end

    if pattern_copy_mode then
        draw_pattern_copy_mode(api, C)
        return
    end

    if preset_selector_mode then
        preset_selector.draw(
            api, C, selected_track,
            function() preset_selector_mode = false end
        )
        return
    end

    if pattern_slots_mode then
        draw_pattern_slots_mode(api, C)
        return
    end

    api.drawstrip(
        8, 1, 8,
        C.PURPLE,
        api.MODE_RADIO,
        {
            group = "edit_value_1_16",
            selected_row = selected_bars <= 8 and 8 or 7,
            selected_col = selected_bars <= 8
                and selected_bars
                or selected_bars - 8,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_bars = pad.col
                api.redraw()
            end
        }
    )

    api.drawstrip(
        7, 1, 8,
        C.PURPLE,
        api.MODE_RADIO,
        {
            group = "edit_value_1_16",
            selected_row = selected_bars <= 8 and 8 or 7,
            selected_col = selected_bars <= 8
                and selected_bars
                or selected_bars - 8,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_bars = 8 + pad.col
                api.redraw()
            end
        }
    )

    api.drawstrip(
        6, 1, 8,
        C.LIGHT_BLUE,
        api.MODE_RADIO,
        {
            group = "edit_region",
            selected_row = 6,
            selected_col = selected_region,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_region = pad.col
                api.redraw()
            end
        }
    )

    api.drawstrip(
        4, 6, 8,
        C.GREEN,
        api.MODE_RADIO,
        {
            group = "edit_scope",
            selected_col = 5 + selected_scope,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_scope = pad.col - 5
                api.redraw()
            end
        }
    )

    api.drawstrip(
        3, 1, 8,
        C.ORANGE,
        api.MODE_RADIO,
        {
            group = "edit_track",
            selected_col = selected_track,
            active_color = C.WHITE,
            on_press = function(pad)
                selected_track = pad.col
                api.redraw()
            end
        }
    )

    api.drawblock(
        2, 1, 1, 8,
        C.BLUE,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            on_press = function(pad)
                if pad.row == ACTION_PATTERN_SLOTS_ROW
                   and pad.col == ACTION_PATTERN_SLOTS_COL then
                    pattern_slot_selected = 1
                    pattern_slot_save_mode = false
                    pattern_preview_session = nil
                    local session, err = pattern_slots.begin_preview(
                        selected_track,
                        selected_region
                    )
                    pattern_preview_session = session
                    if not session and err then
                        reaper.ShowConsoleMsg(
                            "Pattern preview: " .. tostring(err) .. "\n"
                        )
                    end
                    pattern_slots_mode = true
                elseif pad.row == 1 then
                    if pad.col == ACTION_RESIZE_COL then
                        -- Resize starts from the pattern currently selected on
                        -- the Edit overview. Do not fall back to an old resize
                        -- radio-group selection from a previous session.
                        selected_region = clamp(selected_region, 1, 8, 1)
                        resize_mode = true
                    elseif pad.col == ACTION_CLEAR_COL then
                        -- Start every Clear session with both actions disabled.
                        clear_items = false
                        clear_fx = false
                        clear_track_mode = 1
                        clear_mode = true
                    elseif pad.col == ACTION_MERGE_COL then
                        merge_mode = true
                        merge_sequence = {}
                    elseif pad.col == ACTION_TIME_SIGNATURE_COL then
                        time_signature.open()
                        time_signature_mode = true
                    elseif pad.col == ACTION_TRACK_SELECT_COL then
                        subproject_track.open(selected_track)
                        track_select_mode = true
                    elseif pad.col == ACTION_PATTERN_COPY_COL then
                        pattern_copy_mode = true
                        copy_from_region = selected_region
                        copy_to_region = nil
                        copy_track_mode = 1
                    elseif pad.col == ACTION_PRESET_SELECTOR_COL then
                        preset_selector.open(selected_track)
                        preset_selector_mode = true
                    elseif pad.col == ACTION_SAVE_QUIT_COL then
                        save_and_quit.run()
                    end
                end

                api.redraw()
            end
        }
    )
end
