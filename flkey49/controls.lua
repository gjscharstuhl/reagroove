local M = {}

local callbacks = {
    cc_press = {},
    cc_release = {},
    note_press = {},
    note_release = {}
}

function M.on_cc_press(cc, callback)
    callbacks.cc_press[cc] = callback
end

function M.on_cc_release(cc, callback)
    callbacks.cc_release[cc] = callback
end

function M.on_note_press(note, callback)
    callbacks.note_press[note] = callback
end

function M.on_note_release(note, callback)
    callbacks.note_release[note] = callback
end

function M.dispatch_cc(cc, value)
    local callback

    if value > 0 then
        callback = callbacks.cc_press[cc]
    else
        callback = callbacks.cc_release[cc]
    end

    if callback then
        callback(cc, value)
    end
end

function M.dispatch_note(note, velocity)
    local callback

    if velocity > 0 then
        callback = callbacks.note_press[note]
    else
        callback = callbacks.note_release[note]
    end

    if callback then
        callback(note, velocity)
    end
end

return M
