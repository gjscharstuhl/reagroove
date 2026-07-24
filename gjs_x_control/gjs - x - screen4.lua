local scene_api = include("gjs - scene_api.lua")
local playlist_api = include("gjs - playlist_api.lua")

local MODE_LOAD = 1
local MODE_SAVE = 2
local MODE_COPY = 3
local MODE_PLAY = 4

local operation = MODE_LOAD
local active_scene = 1
local selected_copy_scene = nil

local pending_scene = nil
local pending_targets = nil
local pending_generation = 0
local pending_arrived_callback = nil

local playlist_playing = false
local playlist_first_slot = nil
local playlist_last_slot = nil
local playlist_active_slot = nil
local playlist_pending_slot = nil

local SCENE_EMPTY   = { 10, 3, 0 }
local SCENE_SAVED   = { 127, 35, 0 }
local SCENE_PENDING = { 50, 50, 127 }
local SCENE_ACTIVE  = { 127, 127, 127 }

local PLAYLIST_EMPTY   = { 0, 20, 0 }
local PLAYLIST_FILLED  = { 0, 127, 0 }
local PLAYLIST_PENDING = { 50, 50, 127 }
local PLAYLIST_ACTIVE  = { 127, 127, 127 }

local function pad_to_scene(row, col)
    return ((3 - row) * 8) + col
end

local function scene_to_pad(scene_nr)
    if scene_nr <= 8 then
        return 3, scene_nr
    end

    return 2, scene_nr - 8
end

local function pad_to_playlist_slot(row, col)
    return ((5 - row) * 8) + col
end

local function playlist_slot_to_pad(slot)
    if slot <= 8 then
        return 5, slot
    end

    return 4, slot - 8
end

local function show_error(message)
    reaper.ShowConsoleMsg(
        "Screen 4: " .. tostring(message) .. "\n"
    )
end

local function clear_scene_radio(api)
    local state = api.get_screen_state(4)
    state.radio["scene_selection"] = nil
end

local function stop_playlist()
    playlist_playing = false
    playlist_first_slot = nil
    playlist_last_slot = nil
    playlist_active_slot = nil
    playlist_pending_slot = nil
end

local function pending_scene_has_arrived(api)
    if not pending_scene
    or type(pending_targets) ~= "table" then
        return false
    end

    if not api.pattern
    or type(api.pattern.get_visual_state) ~= "function" then
        return false
    end

    for track = 1, 8 do
        local region = pending_targets[track]

        if region then
            local visual_state =
                api.pattern.get_visual_state(
                    track,
                    region
                )

            if visual_state ~= "active" then
                return false
            end
        end
    end

    return true
end

local function show_pending_scene(api, scene_nr)
    local row, col = scene_to_pad(scene_nr)

    api.send_pad_rgb(
        row,
        col,
        SCENE_PENDING[1],
        SCENE_PENDING[2],
        SCENE_PENDING[3]
    )
end

local function show_playlist_pad(api, slot, rgb)
    local row, col = playlist_slot_to_pad(slot)

    api.send_pad_rgb(
        row,
        col,
        rgb[1],
        rgb[2],
        rgb[3]
    )
end

local function redraw_pending_overlays(api)
    if operation ~= MODE_PLAY
    and pending_scene then
        show_pending_scene(api, pending_scene)
    end

    if playlist_active_slot then
        show_playlist_pad(
            api,
            playlist_active_slot,
            PLAYLIST_ACTIVE
        )
    end

    if operation ~= MODE_PLAY
    and playlist_pending_slot then
        show_playlist_pad(
            api,
            playlist_pending_slot,
            PLAYLIST_PENDING
        )
    end
end

local function start_pending_watch(api)
    pending_generation = pending_generation + 1

    local generation = pending_generation

    local function watch()
        if generation ~= pending_generation then
            return
        end

        if not pending_scene then
            return
        end

        if pending_scene_has_arrived(api) then
            local arrived_scene = pending_scene
            local callback = pending_arrived_callback

            active_scene = arrived_scene
            pending_scene = nil
            pending_targets = nil
            pending_arrived_callback = nil

            if callback then
                callback(arrived_scene)
            elseif api.get_current_screen() == 4 then
                api.redraw()
            end

            return
        end

        reaper.defer(watch)
    end

    reaper.defer(watch)
end

local function get_scene_targets(scene_nr)
    if not scene_api.LoadScene(scene_nr) then
        return nil
    end

    local targets = {}

    for track = 1, 8 do
        local region = scene_api.get_pattern(track)

        if region then
            targets[track] = region
        end
    end

    return targets
end

local function queue_scene_now(
    api,
    scene_nr,
    arrived_callback
)
    local targets = get_scene_targets(scene_nr)

    if not targets then
        show_error(
            "scene " .. tostring(scene_nr) ..
            " is niet opgeslagen"
        )
        return false
    end

    pending_scene = scene_nr
    pending_targets = targets
    pending_arrived_callback = arrived_callback

    for track = 1, 8 do
        local region = targets[track]

        if region then
            api.set_track_and_region(track, region)
            api.pattern.select(track, region)
        end
    end

    show_pending_scene(api, scene_nr)
    start_pending_watch(api)

    return true
end

local function queue_scene_at_boundary(
    api,
    scene_nr,
    arrived_callback
)
    local targets = get_scene_targets(scene_nr)

    if not targets then
        show_error(
            "scene " .. tostring(scene_nr) ..
            " is niet opgeslagen"
        )
        return false
    end

    if not api.pattern
    or type(api.pattern.queue_scene) ~= "function" then
        show_error("Pattern.queue_scene ontbreekt")
        return false
    end

    pending_scene = scene_nr
    pending_targets = targets
    pending_arrived_callback = arrived_callback

    show_pending_scene(api, scene_nr)

    return api.pattern.queue_scene(
        targets,
        function()
            start_pending_watch(api)
        end
    )
end

local function load_scene(api, scene_nr)
    stop_playlist()

    return queue_scene_now(
        api,
        scene_nr,
        function()
            if api.get_current_screen() == 4 then
                api.redraw()
            end
        end
    )
end

local function save_scene(scene_nr)
    local success = scene_api.SaveScene(scene_nr)

    if success then
        pending_generation = pending_generation + 1
        pending_scene = nil
        pending_targets = nil
        pending_arrived_callback = nil
        stop_playlist()
        active_scene = scene_nr
    end

    return success
end

local function select_scene_for_copy(scene_nr)
    if not scene_api.GetScene(scene_nr) then
        show_error(
            "scene " .. tostring(scene_nr) ..
            " is niet opgeslagen"
        )
        return false
    end

    selected_copy_scene = scene_nr
    return true
end

local function toggle_selected_scene_in_slot(slot)
    -- Gevuld playlistslot opnieuw indrukken = verwijderen.
    if playlist_api.IsFilled(slot) then
        return playlist_api.Clear(slot)
    end

    if not selected_copy_scene then
        show_error("selecteer eerst een opgeslagen scene")
        return false
    end

    return playlist_api.Set(
        slot,
        selected_copy_scene
    )
end

local queue_playlist_slot

queue_playlist_slot = function(
    api,
    slot,
    wait_for_boundary
)
    if not playlist_playing then
        return false
    end

    local scene_nr = playlist_api.Get(slot)

    if not scene_nr then
        stop_playlist()
        show_error(
            "playlist slot " .. tostring(slot) ..
            " is leeg"
        )
        return false
    end

    playlist_pending_slot = slot

    if api.get_current_screen() == 4 then
        api.redraw()
    end

    local function arrived()
        if not playlist_playing then
            return
        end

        playlist_active_slot = slot
        playlist_pending_slot = nil

        local next_slot =
            playlist_api.NextInGroup(
                slot,
                playlist_first_slot,
                playlist_last_slot
            )

        if not next_slot then
            stop_playlist()

            if api.get_current_screen() == 4 then
                api.redraw()
            end

            return
        end

        -- De volgende scene wordt nu pas vlak voor de volgende
        -- scenegrens door Pattern.update geactiveerd.
        queue_playlist_slot(
            api,
            next_slot,
            true
        )

        if api.get_current_screen() == 4 then
            api.redraw()
        end
    end

    if wait_for_boundary then
        return queue_scene_at_boundary(
            api,
            scene_nr,
            arrived
        )
    end

    return queue_scene_now(
        api,
        scene_nr,
        arrived
    )
end

local function start_playlist(api, slot)
    if not playlist_api.IsFilled(slot) then
        show_error(
            "playlist slot " .. tostring(slot) ..
            " is leeg"
        )
        return false
    end

    local first_slot, last_slot =
        playlist_api.FindGroup(slot)

    if not first_slot or not last_slot then
        return false
    end

    pending_generation = pending_generation + 1
    pending_scene = nil
    pending_targets = nil
    pending_arrived_callback = nil

    playlist_playing = true
    playlist_first_slot = first_slot
    playlist_last_slot = last_slot
    playlist_active_slot = nil
    playlist_pending_slot = slot

    clear_scene_radio(api)

    if api.transport and api.transport.play then
        api.transport.play()
    end

    -- Alleen het aangeklikte startslot wordt onmiddellijk geladen.
    return queue_playlist_slot(
        api,
        slot,
        false
    )
end

local function press_scene(api, scene_nr)
    if operation == MODE_LOAD then
        return load_scene(api, scene_nr)
    elseif operation == MODE_SAVE then
        return save_scene(scene_nr)
    elseif operation == MODE_COPY then
        return select_scene_for_copy(scene_nr)
    end

    return false
end

local function drawscreen4(api)
    local C = api.COLOR

    api.drawblock(
        8, 1,
        7, 8,
        C.GREY,
        api.MODE_RADIO,
        {
            group = "scenes_patterns",
            selected_row = 8,
            selected_col = 1,
            active_color = C.WHITE
        }
    )

    api.drawstrip(
        6, 1, 8,
        C.LIGHT_BLUE,
        api.MODE_RADIO,
        {
            group = "scenes_regions",
            selected_col = 1,
            active_color = C.WHITE
        }
    )

    local function playlist_background_rgb(row, col)
        local slot = pad_to_playlist_slot(row, col)

        if slot == playlist_active_slot then
            return PLAYLIST_ACTIVE
        elseif operation ~= MODE_PLAY
        and slot == playlist_pending_slot then
            return PLAYLIST_PENDING
        elseif playlist_api.IsFilled(slot) then
            return PLAYLIST_FILLED
        end

        return PLAYLIST_EMPTY
    end

    api.drawblock(
        5, 1,
        4, 8,
        C.OFF,
        api.MODE_HIGHLIGHT,
        {
            active_color = C.WHITE,
            background_rgb = playlist_background_rgb,

            on_press = function(pad)
                local slot =
                    pad_to_playlist_slot(
                        pad.row,
                        pad.col
                    )

                if operation == MODE_COPY then
                    if toggle_selected_scene_in_slot(slot) then
                        api.redraw()
                    end
                elseif operation == MODE_PLAY then
                    start_playlist(api, slot)
                end
            end
        }
    )

    local displayed_scene = nil

    if operation == MODE_COPY then
        displayed_scene = selected_copy_scene
    elseif operation == MODE_PLAY then
        -- In PLAY volgt de witte scene-indicatie uitsluitend
        -- het werkelijk actieve playlistslot.
        if playlist_active_slot then
            displayed_scene =
                playlist_api.Get(playlist_active_slot)
        end
    else
        displayed_scene = active_scene
    end

    local active_row
    local active_col

    if displayed_scene
    and operation ~= MODE_PLAY then
        -- Buiten PLAY blijft de bestaande radioselectie actief.
        -- In PLAY wordt wit uitsluitend via background_rgb getekend,
        -- zodat er geen kortstondige radio-highlight kan knipperen.
        active_row, active_col =
            scene_to_pad(displayed_scene)
    end

    local function scene_background_rgb(row, col)
        local scene_nr = pad_to_scene(row, col)

        if operation ~= MODE_PLAY
        and scene_nr == pending_scene then
            return SCENE_PENDING
        end

        if operation == MODE_COPY then
            -- Bij het openen van COPY verdwijnt alleen de witte selectie.
            -- Alle opgeslagen scenes blijven helder oranje zichtbaar.
            if scene_nr == selected_copy_scene then
                return SCENE_ACTIVE
            elseif scene_api.GetScene(scene_nr) then
                return SCENE_SAVED
            end

            return SCENE_EMPTY
        end

        if operation == MODE_PLAY then
            if scene_nr == displayed_scene then
                return SCENE_ACTIVE
            elseif scene_api.GetScene(scene_nr) then
                return SCENE_SAVED
            end

            return SCENE_EMPTY
        end

        if scene_nr == active_scene then
            return SCENE_ACTIVE
        elseif scene_api.GetScene(scene_nr) then
            return SCENE_SAVED
        end

        return SCENE_EMPTY
    end

    api.drawblock(
        3, 1,
        2, 8,
        C.OFF,
        api.MODE_RADIO,
        {
            group = "scene_selection",
            selected_row = active_row,
            selected_col = active_col,
            active_color = C.WHITE,
            background_rgb = scene_background_rgb,

            on_press = function(pad)
                if operation == MODE_PLAY then
                    return
                end

                local scene_nr =
                    pad_to_scene(
                        pad.row,
                        pad.col
                    )

                if press_scene(api, scene_nr) then
                    if operation ~= MODE_LOAD then
                        api.redraw()
                    end
                end
            end
        }
    )

    redraw_pending_overlays(api)

    api.drawstrip(
        1, 1, 8,
        C.ORANGE,
        api.MODE_RADIO,
        {
            group = "scenes_operations",
            selected_col = operation,
            active_color = C.WHITE,

            on_press = function(pad)
                operation = pad.col

                selected_copy_scene = nil
                stop_playlist()

                if operation == MODE_COPY
                or operation == MODE_PLAY then
                    clear_scene_radio(api)
                end

                api.redraw()
            end
        }
    )
end

return drawscreen4
