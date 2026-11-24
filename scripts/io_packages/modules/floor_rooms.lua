local log = require("helpers.log")

local ROOM_ENTRY_SIZE = 0x98
local MAX_ROOM_COUNT = 30
local LAYOUT_RECORD_OFFSET = 0x80
local STATE_RECORD_OFFSET = 0x88
local LAYOUT_ROOM_TYPE_OFFSET = 0x02
local FLOOR_CURRENT_ROOM_OFFSET = 0x01
local OUTSIDE_ROOM_ID = 0
local START_ROOM_TYPE = 1
local STATE_VISITED_OFFSET = 0x05
local VISITED = 1

local function get_room_entry(room_number)
    return BASE_ADDR + floorRoomEntries + room_number * ROOM_ENTRY_SIZE
end

local function read_room(room_number)
    local room_entry = get_room_entry(room_number)
    local layout = ReadLong(room_entry + LAYOUT_RECORD_OFFSET, true)
    local state = ReadLong(room_entry + STATE_RECORD_OFFSET, true)
    if layout == 0 or state == 0 then
        return nil
    end
    local room = {}
    room.number = room_number
    room.entry = room_entry
    room.id = ReadShort(layout, true)
    room.room_type = ReadShort(layout + LAYOUT_ROOM_TYPE_OFFSET, true)
    room.state = state
    return room
end

local function read_floor_rooms()
    local rooms = {}
    local room_count = ReadShort(floorRoomCount)
    if room_count > MAX_ROOM_COUNT then
        log.log_debug("floor rooms: room count " .. tostring(room_count) .. " looks wrong")
        return rooms
    end
    for room_number = 0, room_count - 1 do
        local room = read_room(room_number)
        if room ~= nil then
            rooms[#rooms + 1] = room
        end
    end
    return rooms
end

local function is_outside_floor()
    local floor_state = ReadLong(floorStatePointer)
    if floor_state == 0 then
        return false
    end
    if ReadShort(floorRoomCount) == 0 then
        return false
    end
    return ReadByte(floor_state + FLOOR_CURRENT_ROOM_OFFSET, true) == OUTSIDE_ROOM_ID
end

local function is_floor_started()
    local rooms = read_floor_rooms()
    for _, room in ipairs(rooms) do
        if room.room_type == START_ROOM_TYPE then
            return ReadByte(room.state + STATE_VISITED_OFFSET, true) == VISITED
        end
    end
    return false
end

return {
    is_outside_floor = is_outside_floor,
    is_floor_started = is_floor_started
}
