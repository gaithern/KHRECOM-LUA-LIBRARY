local log = require("helpers.log")
local memory_values = require("helpers.memory_values")

local FLOOR_COUNT = 13
local FIRST_WORLD = 1
local LAST_WORLD = 13
local LAST_FLOOR_WORLD = 13

local TABLE_ENTRY_SIZE = 2
local VANILLA_TABLE = {4, 6, 7, 8, 9, 10, 12, 11, 13, 11, 12, 13}

local FIRST_FLOOR_CODE = {0xB8, 0x09, 0x00, 0x00, 0x00, 0x85, 0xC9, 0x41, 0x0F, 0x45, 0xC5}
local FIRST_FLOOR_WORLD_OFFSET = 1
local FIRST_FLOOR_CHOICE_OFFSET = 7
local FIRST_FLOOR_CHOICE_CODE = {0x41, 0x0F, 0x45, 0xC5}
local NO_OPERATION = 0x90
local JUMP_IF_NOT_LESS = 0x7D
local JUMP_ALWAYS = 0xEB
local FIRST_JUMP_DISTANCE = 0x6D
local SECOND_JUMP_DISTANCE = 0x65

local BYTE_VARIABLES_POINTER_OFFSET = 8
local VARIABLE_BYTES_OFFSET = 0x8
local STORY_VARIABLE = 0x60
local SORA_STORY = 0

local world_order = nil
local reported_problems = {}

local function report_once(message)
    if reported_problems[message] then
        return
    end
    reported_problems[message] = true
    log.log_debug("world order: " .. message)
end

local function set_world_order(worlds)
    if type(worlds) ~= "table" or #worlds ~= FLOOR_COUNT then
        log.log_debug("world order: the order must be a list of 13 world ids, floor 1 first")
        return false
    end
    local used = {}
    for floor = 1, FLOOR_COUNT do
        local world_id = worlds[floor]
        if not memory_values.is_whole_number(world_id, FIRST_WORLD, LAST_WORLD) then
            log.log_debug("world order: every world id must be from 1 to 13")
            return false
        end
        if used[world_id] then
            log.log_debug("world order: world " .. world_id .. " is in the order twice")
            return false
        end
        used[world_id] = true
    end
    if worlds[FLOOR_COUNT] ~= LAST_FLOOR_WORLD then
        log.log_debug("world order: floor 13 must be Castle Oblivion (13)")
        return false
    end
    world_order = worlds
    return true
end

local function is_sora_story()
    local variables_pointer = timePlayedPointer + BYTE_VARIABLES_POINTER_OFFSET
    if ReadLong(variables_pointer) == 0 then
        return false
    end
    local bytes_address = ReadLong(GetPointer(variables_pointer, VARIABLE_BYTES_OFFSET), true)
    if bytes_address == 0 then
        return false
    end
    return ReadByte(bytes_address + STORY_VARIABLE, true) == SORA_STORY
end

local function keep_exe_byte(address, value)
    if ReadByte(address) ~= value then
        WriteByte(address, value)
    end
end

local function keep_exe_short(address, value)
    if ReadShort(address) ~= value then
        WriteShort(address, value)
    end
end

local function is_jump_known(address, distance)
    local opcode = ReadByte(address)
    if opcode ~= JUMP_IF_NOT_LESS and opcode ~= JUMP_ALWAYS then
        return false
    end
    return ReadByte(address + 1) == distance
end

local function is_first_floor_choice_known()
    local vanilla = true
    local changed = true
    for index, value in ipairs(FIRST_FLOOR_CHOICE_CODE) do
        local current = ReadByte(worldSelectFirstFloorCode + FIRST_FLOOR_CHOICE_OFFSET + index - 1)
        if current ~= value then
            vanilla = false
        end
        if current ~= NO_OPERATION then
            changed = false
        end
    end
    return vanilla or changed
end

local function is_code_known()
    if ReadByte(worldSelectFirstFloorCode) ~= FIRST_FLOOR_CODE[1] then
        return false
    end
    if not is_first_floor_choice_known() then
        return false
    end
    if not is_jump_known(worldSelectFirstJump, FIRST_JUMP_DISTANCE) then
        return false
    end
    return is_jump_known(worldSelectSecondJump, SECOND_JUMP_DISTANCE)
end

local function write_new_order()
    for floor = 2, FLOOR_COUNT do
        keep_exe_short(worldSelectOneWorldTable + (floor - 2) * TABLE_ENTRY_SIZE, world_order[floor])
    end
    keep_exe_byte(worldSelectFirstFloorCode + FIRST_FLOOR_WORLD_OFFSET, world_order[1])
    for index = 1, #FIRST_FLOOR_CHOICE_CODE do
        keep_exe_byte(worldSelectFirstFloorCode + FIRST_FLOOR_CHOICE_OFFSET + index - 1, NO_OPERATION)
    end
    keep_exe_byte(worldSelectFirstJump, JUMP_ALWAYS)
    keep_exe_byte(worldSelectSecondJump, JUMP_ALWAYS)
end

local function write_vanilla_order()
    for index, world_id in ipairs(VANILLA_TABLE) do
        keep_exe_short(worldSelectOneWorldTable + (index - 1) * TABLE_ENTRY_SIZE, world_id)
    end
    for index, value in ipairs(FIRST_FLOOR_CODE) do
        keep_exe_byte(worldSelectFirstFloorCode + index - 1, value)
    end
    keep_exe_byte(worldSelectFirstJump, JUMP_IF_NOT_LESS)
    keep_exe_byte(worldSelectSecondJump, JUMP_IF_NOT_LESS)
end

local function apply_world_order()
    if world_order == nil then
        return
    end
    if not is_code_known() then
        report_once("the world select code is not where it should be")
        return
    end
    if is_sora_story() then
        write_new_order()
    else
        write_vanilla_order()
    end
end

return {
    set_world_order = set_world_order,
    is_sora_story = is_sora_story,
    apply_world_order = apply_world_order
}
