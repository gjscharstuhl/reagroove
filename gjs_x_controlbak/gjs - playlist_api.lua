-- ============================================================
-- gjs - playlist_api.lua
-- In-memory playlist storage and group helpers for 16 scenes
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

function M.FindGroup(slot)
    slot = valid_slot(slot)

    if not slot or not M.IsFilled(slot) then
        return nil, nil
    end

    local first_slot = slot
    local last_slot = slot

    while first_slot > 1
      and M.IsFilled(first_slot - 1) do
        first_slot = first_slot - 1
    end

    while last_slot < SLOT_COUNT
      and M.IsFilled(last_slot + 1) do
        last_slot = last_slot + 1
    end

    return first_slot, last_slot
end

function M.NextInGroup(slot, first_slot, last_slot)
    slot = valid_slot(slot)
    first_slot = valid_slot(first_slot)
    last_slot = valid_slot(last_slot)

    if not slot or not first_slot or not last_slot then
        return nil
    end

    if slot < first_slot or slot > last_slot then
        return nil
    end

    if slot < last_slot then
        return slot + 1
    end

    return first_slot
end

return M
