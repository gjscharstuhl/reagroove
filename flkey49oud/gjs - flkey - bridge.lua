local Bridge = {}

local GMEM_NAME = "GJS_FLKEY_BRIDGE"
local QUEUE_BASE = 16
local CAPACITY = 64
local RECORD_SIZE = 64

local attached = false

local function attach()
    if not attached then
        reaper.gmem_attach(GMEM_NAME)
        attached = true
    end
end

local function clamp7(value)
    value = math.floor(tonumber(value) or 0)
    if value < 0 then return 0 end
    if value > 127 then return 127 end
    return value
end

local function valid_position(value, capacity)
    return value >= 0
       and value < capacity
       and value == math.floor(value)
end

local function push(command, args)
    args = args or {}
    attach()

    if reaper.gmem_read(4) == 0 then
        return false, "FLkey JSFX bridge is niet actief"
    end

    local capacity = math.floor(reaper.gmem_read(2))
    local record_size = math.floor(reaper.gmem_read(3))

    if capacity ~= CAPACITY or record_size ~= RECORD_SIZE then
        return false, "Onverwachte bridgeversie of beschadigde queue"
    end

    if #args > record_size - 2 then
        return false, "Te veel argumenten voor bridge-opdracht"
    end

    local write_pos = reaper.gmem_read(0)
    local read_pos = reaper.gmem_read(1)

    if not valid_position(write_pos, capacity)
       or not valid_position(read_pos, capacity) then
        return false, "Ongeldige bridge-queuepositie"
    end

    write_pos = math.floor(write_pos)
    read_pos = math.floor(read_pos)

    local next_pos = (write_pos + 1) % capacity

    if next_pos == read_pos then
        reaper.gmem_write(5, reaper.gmem_read(5) + 1)
        return false, "FLkey bridge queue is vol"
    end

    local base = QUEUE_BASE + write_pos * record_size
    reaper.gmem_write(base, command)
    reaper.gmem_write(base + 1, #args)

    for i = 1, #args do
        reaper.gmem_write(base + 1 + i, args[i])
    end

    reaper.gmem_write(0, next_pos)
    return true
end

function Bridge.init()
    attach()

    return reaper.gmem_read(4) ~= 0
       and math.floor(reaper.gmem_read(2)) == CAPACITY
       and math.floor(reaper.gmem_read(3)) == RECORD_SIZE
end

function Bridge.daw_mode(enabled)
    return push(1, { enabled and 1 or 0 })
end

function Bridge.set_pad_layout(layout)
    return push(2, { clamp7(layout) })
end

function Bridge.set_pad_rgb(note, red, green, blue)
    return push(7, {
        0,
        clamp7(note),
        clamp7(red),
        clamp7(green),
        clamp7(blue)
    })
end

function Bridge.set_cc_rgb(cc, red, green, blue)
    return push(7, {
        1,
        clamp7(cc),
        clamp7(red),
        clamp7(green),
        clamp7(blue)
    })
end

return Bridge
