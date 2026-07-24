-- ============================================================
-- gjs - playlist_api.lua
-- In-memory playlist storage for 16 scene slots
-- ============================================================

local M = {}

local SLOT_COUNT = 16
local slots = {}

local function valid_slot(slot)
    slot = tonumber(slot)

    if not slot then
        return nil
    end

    slot = math.floor(slot)

    if slot < 1 or slot > SLOT_COUNT then
        return nil
    end

    return slot
end

local function valid_scene(scene_nr)
    scene_nr = tonumber(scene_nr)

    if not scene_nr then
        return nil
    end

    scene_nr = math.floor(scene_nr)

    if scene_nr < 1 or scene_nr > 16 then
        return nil
    end

    return scene_nr
end

function M.GetSlotCount()
    return SLOT_COUNT
end

function M.Get(slot)
    slot = valid_slot(slot)

    if not slot then
        return nil
    end

    return slots[slot]
end

function M.Set(slot, scene_nr)
    slot = valid_slot(slot)
    scene_nr = valid_scene(scene_nr)

    if not slot or not scene_nr then
        return false
    end

    slots[slot] = scene_nr
    return true
end

function M.IsFilled(slot)
    return M.Get(slot) ~= nil
end

function M.Clear(slot)
    slot = valid_slot(slot)

    if not slot then
        return false
    end

    slots[slot] = nil
    return true
end

function M.ClearAll()
    slots = {}
end

function M.GetSlots()
    return slots
end

return M
