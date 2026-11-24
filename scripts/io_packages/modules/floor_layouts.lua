local log = require("helpers.log")
local memory_values = require("helpers.memory_values")
local loaded_files = require("modules.loaded_files")

local LAYOUT_FILE = "rooms1.bin"
local LAYOUT_VERSION = 4
local VERSION_OFFSET = 0x04
local FLOOR_COUNT_OFFSET = 0x06
local FLOOR_TABLE_OFFSET = 0x08
local FLOOR_DATA_OFFSET = 0x0C
local FLOOR_ID_OFFSET = 0x00
local FLOOR_ROOM_COUNT_OFFSET = 0x02
local FLOOR_WIDTH_OFFSET = 0x04
local FLOOR_DEPTH_OFFSET = 0x06
local FLOOR_START_SCENE_OFFSET = 0x08
local FLOOR_GOAL_SCENE_OFFSET = 0x0A
local FIRST_START_SCENE = 2001
local FIRST_GOAL_SCENE = 2002
local SCENES_PER_FLOOR = 2
local MOVABLE_FLOOR_COUNT = 12
local FLOOR_TABLE_ENTRY_SIZE = 4
local MAX_FLOOR_SIZE = 7
local FIRST_ROOM_OFFSET = 0x10
local ROOM_SIZE = 0x1C
local ROOM_ID_OFFSET = 0x00
local ROOM_TYPE_OFFSET = 0x02
local ROOM_FIX_SCENE_OFFSET = 0x04
local ROOM_X_OFFSET = 0x08
local ROOM_Y_OFFSET = 0x0A
local FIRST_DOOR_OFFSET = 0x0C
local DOOR_SIZE = 4
local DOOR_DESTINATION_OFFSET = 0
local DOOR_TYPE_OFFSET = 2
local DOOR_CHECK_EVENT_OFFSET = 3
local DOOR_COUNT = 4
local MAX_FIX_SCENE = 32767
local MAX_POSITION = 32767
local MAX_CHECK_EVENT = 255

local ROOM_TYPES = {
    CARD = 0,
    START = 1,
    EVENT_1 = 2,
    EVENT_2 = 3,
    EVENT_3 = 4,
    GOAL = 5,
    EXTRA = 6,
    LAST = 7,
    FIX = 8
}

local DOOR_TYPES = {
    NORMAL = 0,
    TO_EVENT_1 = 1,
    TO_EVENT_2 = 2,
    TO_EVENT_3 = 3,
    OPEN_AFTER_EVENT = 4,
    TO_GOAL = 5,
    TO_EXTRA = 6,
    ONE_WAY = 7,
    WORLD_ENTRANCE = 8,
    SELECT_WORLD = 9,
    FLOOR_CHANGE = 10,
    TO_LAST = 11,
    EVENT_ROOM = 12,
    DEBUG = 13
}

local layout_order = nil
local size_changes = {}
local room_changes = {}
local door_changes = {}
local reported_problems = {}

local function report_once(message)
    if reported_problems[message] then
        return
    end
    reported_problems[message] = true
    log.log_debug("floor layouts: " .. message)
end

local function find_floor(file_data, floor_id)
    if ReadShort(file_data + VERSION_OFFSET, true) ~= LAYOUT_VERSION then
        return nil
    end
    local floor_count = ReadShort(file_data + FLOOR_COUNT_OFFSET, true)
    local floor_table = file_data + ReadInt(file_data + FLOOR_TABLE_OFFSET, true)
    local floor_data = file_data + ReadInt(file_data + FLOOR_DATA_OFFSET, true)
    for floor_index = 0, floor_count - 1 do
        local floor_address = floor_data + ReadInt(floor_table + floor_index * 4, true)
        if memory_values.read_signed_short(floor_address + FLOOR_ID_OFFSET) == floor_id then
            return floor_address
        end
    end
    return nil
end

local function get_room_count(floor_address)
    return memory_values.read_signed_short(floor_address + FLOOR_ROOM_COUNT_OFFSET)
end

local function get_room_address(floor_address, room_id)
    if room_id < 1 or room_id > get_room_count(floor_address) then
        return nil
    end
    local room_address = floor_address + FIRST_ROOM_OFFSET + (room_id - 1) * ROOM_SIZE
    if memory_values.read_signed_short(room_address + ROOM_ID_OFFSET) ~= room_id then
        return nil
    end
    return room_address
end

local function get_door_address(room_address, door_number)
    return room_address + FIRST_DOOR_OFFSET + (door_number - 1) * DOOR_SIZE
end

local function read_door(door_address)
    local door = {}
    door.destination = memory_values.read_signed_short(door_address + DOOR_DESTINATION_OFFSET)
    door.type = ReadByte(door_address + DOOR_TYPE_OFFSET, true)
    door.check_event = ReadByte(door_address + DOOR_CHECK_EVENT_OFFSET, true)
    return door
end

local function read_room(room_address)
    local room = {}
    room.id = memory_values.read_signed_short(room_address + ROOM_ID_OFFSET)
    room.type = memory_values.read_signed_short(room_address + ROOM_TYPE_OFFSET)
    room.fix_scene = memory_values.read_signed_short(room_address + ROOM_FIX_SCENE_OFFSET)
    room.x = memory_values.read_signed_short(room_address + ROOM_X_OFFSET)
    room.y = memory_values.read_signed_short(room_address + ROOM_Y_OFFSET)
    room.doors = {}
    for door_number = 1, DOOR_COUNT do
        room.doors[door_number] = read_door(get_door_address(room_address, door_number))
    end
    return room
end

local function get_floor_layout(floor_id)
    local file_data = loaded_files.find_loaded_file(LAYOUT_FILE)
    if file_data == nil then
        return nil
    end
    local floor_address = find_floor(file_data, floor_id)
    if floor_address == nil then
        return nil
    end
    local layout = {}
    layout.floor_id = floor_id
    layout.rooms = {}
    for room_id = 1, get_room_count(floor_address) do
        local room_address = get_room_address(floor_address, room_id)
        if room_address ~= nil then
            layout.rooms[room_id] = read_room(room_address)
        end
    end
    return layout
end

local function set_floor_layout_order(layouts)
    if type(layouts) ~= "table" or #layouts ~= MOVABLE_FLOOR_COUNT then
        log.log_debug("floor layouts: the layout order must be a list of 12 layout numbers, floor 1 first")
        return false
    end
    local used = {}
    for floor = 1, MOVABLE_FLOOR_COUNT do
        local layout = layouts[floor]
        if not memory_values.is_whole_number(layout, 1, MOVABLE_FLOOR_COUNT) then
            log.log_debug("floor layouts: every layout number must be from 1 to 12")
            return false
        end
        if used[layout] then
            log.log_debug("floor layouts: layout " .. layout .. " is in the order twice")
            return false
        end
        used[layout] = true
    end
    layout_order = layouts
    return true
end

local function set_floor_size(floor_id, width, depth)
    if not memory_values.is_whole_number(floor_id, 1, MOVABLE_FLOOR_COUNT) then
        log.log_debug("floor layouts: the size can be set on floors 1 to 12")
        return false
    end
    if not memory_values.is_whole_number(width, 1, MAX_FLOOR_SIZE) then
        log.log_debug("floor layouts: the width must be from 1 to 7")
        return false
    end
    if not memory_values.is_whole_number(depth, 1, MAX_FLOOR_SIZE) then
        log.log_debug("floor layouts: the depth must be from 1 to 7")
        return false
    end
    size_changes[floor_id] = {width = width, depth = depth}
    return true
end

local function is_optional_number(value, lowest, highest)
    if value == nil then
        return true
    end
    return memory_values.is_whole_number(value, lowest, highest)
end

local function set_floor_room(floor_id, room_id, room)
    if not memory_values.is_whole_number(floor_id, 1, MAX_POSITION) then
        log.log_debug("floor layouts: floor id must be a whole number (1-15, 100 for 100 Acre Wood)")
        return false
    end
    if not memory_values.is_whole_number(room_id, 1, MAX_POSITION) then
        log.log_debug("floor layouts: room id must be a whole number from 1")
        return false
    end
    if type(room) ~= "table" then
        log.log_debug("floor layouts: room changes must be a table")
        return false
    end
    if not is_optional_number(room.type, ROOM_TYPES.CARD, ROOM_TYPES.FIX) then
        log.log_debug("floor layouts: room type must be one of FLOOR_ROOM_TYPES")
        return false
    end
    if not is_optional_number(room.fix_scene, 0, MAX_FIX_SCENE) then
        log.log_debug("floor layouts: fix scene must be from 0 to 32767")
        return false
    end
    if not is_optional_number(room.x, 0, MAX_POSITION) or not is_optional_number(room.y, 0, MAX_POSITION) then
        log.log_debug("floor layouts: room x and y must be from 0 to 32767")
        return false
    end
    if room_changes[floor_id] == nil then
        room_changes[floor_id] = {}
    end
    room_changes[floor_id][room_id] = room
    return true
end

local function set_floor_door(floor_id, room_id, door_number, door)
    if not memory_values.is_whole_number(floor_id, 1, MAX_POSITION) then
        log.log_debug("floor layouts: floor id must be a whole number (1-15, 100 for 100 Acre Wood)")
        return false
    end
    if not memory_values.is_whole_number(room_id, 1, MAX_POSITION) then
        log.log_debug("floor layouts: room id must be a whole number from 1")
        return false
    end
    if not memory_values.is_whole_number(door_number, 1, DOOR_COUNT) then
        log.log_debug("floor layouts: door number must be from 1 to 4")
        return false
    end
    if type(door) ~= "table" then
        log.log_debug("floor layouts: door changes must be a table")
        return false
    end
    if not is_optional_number(door.destination, 0, MAX_POSITION) then
        log.log_debug("floor layouts: door destination must be a room id, or 0 for no door")
        return false
    end
    if not is_optional_number(door.type, DOOR_TYPES.NORMAL, DOOR_TYPES.DEBUG) then
        log.log_debug("floor layouts: door type must be one of FLOOR_DOOR_TYPES")
        return false
    end
    if not is_optional_number(door.check_event, 0, MAX_CHECK_EVENT) then
        log.log_debug("floor layouts: door check event must be from 0 to 255")
        return false
    end
    if door_changes[floor_id] == nil then
        door_changes[floor_id] = {}
    end
    if door_changes[floor_id][room_id] == nil then
        door_changes[floor_id][room_id] = {}
    end
    door_changes[floor_id][room_id][door_number] = door
    return true
end

local function keep_byte_if_set(address, value)
    if value ~= nil then
        memory_values.keep_byte(address, value)
    end
end

local function keep_short_if_set(address, value)
    if value ~= nil then
        memory_values.keep_short(address, value)
    end
end

local function apply_room(room_address, room)
    keep_short_if_set(room_address + ROOM_TYPE_OFFSET, room.type)
    keep_short_if_set(room_address + ROOM_FIX_SCENE_OFFSET, room.fix_scene)
    keep_short_if_set(room_address + ROOM_X_OFFSET, room.x)
    keep_short_if_set(room_address + ROOM_Y_OFFSET, room.y)
end

local function apply_door(floor_address, door_address, door)
    if door.destination ~= nil and door.destination > get_room_count(floor_address) then
        report_once("a door leads to room " .. door.destination .. " but its floor has only " .. get_room_count(floor_address) .. " rooms")
        return
    end
    keep_short_if_set(door_address + DOOR_DESTINATION_OFFSET, door.destination)
    keep_byte_if_set(door_address + DOOR_TYPE_OFFSET, door.type)
    keep_byte_if_set(door_address + DOOR_CHECK_EVENT_OFFSET, door.check_event)
end

local function apply_floor_rooms(file_data, floor_id, rooms)
    local floor_address = find_floor(file_data, floor_id)
    if floor_address == nil then
        report_once("there is no floor with id " .. floor_id)
        return
    end
    for room_id, room in pairs(rooms) do
        local room_address = get_room_address(floor_address, room_id)
        if room_address == nil then
            report_once("floor " .. floor_id .. " has no room " .. room_id)
        else
            apply_room(room_address, room)
        end
    end
end

local function apply_floor_doors(file_data, floor_id, rooms)
    local floor_address = find_floor(file_data, floor_id)
    if floor_address == nil then
        report_once("there is no floor with id " .. floor_id)
        return
    end
    for room_id, doors in pairs(rooms) do
        local room_address = get_room_address(floor_address, room_id)
        if room_address == nil then
            report_once("floor " .. floor_id .. " has no room " .. room_id)
        else
            for door_number, door in pairs(doors) do
                apply_door(floor_address, get_door_address(room_address, door_number), door)
            end
        end
    end
end

local function get_movable_offsets(floor_table)
    local offsets = {}
    for floor_index = 0, MOVABLE_FLOOR_COUNT - 1 do
        offsets[floor_index + 1] = ReadInt(floor_table + floor_index * FLOOR_TABLE_ENTRY_SIZE, true)
    end
    table.sort(offsets)
    return offsets
end

local function apply_layout_order(file_data)
    if layout_order == nil or ReadShort(file_data + VERSION_OFFSET, true) ~= LAYOUT_VERSION then
        return
    end
    local floor_table = file_data + ReadInt(file_data + FLOOR_TABLE_OFFSET, true)
    local floor_data = file_data + ReadInt(file_data + FLOOR_DATA_OFFSET, true)
    local offsets = get_movable_offsets(floor_table)
    for floor = 1, MOVABLE_FLOOR_COUNT do
        local offset = offsets[layout_order[floor]]
        local floor_address = floor_data + offset
        memory_values.keep_int(floor_table + (floor - 1) * FLOOR_TABLE_ENTRY_SIZE, offset)
        memory_values.keep_short(floor_address + FLOOR_ID_OFFSET, floor)
        memory_values.keep_short(floor_address + FLOOR_START_SCENE_OFFSET, FIRST_START_SCENE + (floor - 1) * SCENES_PER_FLOOR)
        memory_values.keep_short(floor_address + FLOOR_GOAL_SCENE_OFFSET, FIRST_GOAL_SCENE + (floor - 1) * SCENES_PER_FLOOR)
    end
end

local function apply_floor_sizes(file_data)
    for floor_id, size in pairs(size_changes) do
        local floor_address = find_floor(file_data, floor_id)
        if floor_address ~= nil then
            memory_values.keep_short(floor_address + FLOOR_WIDTH_OFFSET, size.width)
            memory_values.keep_short(floor_address + FLOOR_DEPTH_OFFSET, size.depth)
        end
    end
end

local function apply_floor_layouts(file_map)
    local file_data = file_map[LAYOUT_FILE]
    if file_data == nil then
        return
    end
    apply_layout_order(file_data)
    apply_floor_sizes(file_data)
    for floor_id, rooms in pairs(room_changes) do
        apply_floor_rooms(file_data, floor_id, rooms)
    end
    for floor_id, rooms in pairs(door_changes) do
        apply_floor_doors(file_data, floor_id, rooms)
    end
end

return {
    ROOM_TYPES = ROOM_TYPES,
    DOOR_TYPES = DOOR_TYPES,
    get_floor_layout = get_floor_layout,
    set_floor_layout_order = set_floor_layout_order,
    set_floor_size = set_floor_size,
    set_floor_room = set_floor_room,
    set_floor_door = set_floor_door,
    apply_floor_layouts = apply_floor_layouts
}
