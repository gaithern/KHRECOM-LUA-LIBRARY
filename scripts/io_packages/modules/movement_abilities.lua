local log = require("helpers.log")
local world_order = require("modules.world_order")

local ABILITY_VARIABLE_OFFSET = 0x90
local SLEIGHTS_PER_BYTE = 4
local SLEIGHT_STATE_COUNT = 4
local ABILITIES = {
    {name = "High Jump", sleight = 0x5A, flag = 1},
    {name = "Glide", sleight = 0x5B, flag = 2},
    {name = "Superglide", sleight = 0x5C, flag = 4}
}

local follow_sleights = false

local function set_movement_abilities_follow_sleights(wanted)
    if type(wanted) ~= "boolean" then
        log.log_debug("movement abilities: wanted must be true or false")
        return false
    end
    follow_sleights = wanted
    return true
end

local function is_sleight_owned(sleight)
    local byte_number = math.floor(sleight / SLEIGHTS_PER_BYTE)
    local position = sleight % SLEIGHTS_PER_BYTE
    local states = ReadByte(GetPointer(journalPointer, byte_number), true)
    for _ = 1, position do
        states = math.floor(states / SLEIGHT_STATE_COUNT)
    end
    return states % SLEIGHT_STATE_COUNT ~= 0
end

local function get_variable_address()
    if ReadLong(timePlayedPointer) == 0 then
        return nil
    end
    local variables_address = ReadLong(GetPointer(timePlayedPointer, TIME_PLAYED_FIRST_OFFSET), true)
    if variables_address == 0 then
        return nil
    end
    return variables_address + ABILITY_VARIABLE_OFFSET
end

local function has_flag(flags, flag)
    return math.floor(flags / flag) % 2 == 1
end

local function get_wanted_flags(flags)
    local wanted = flags
    for _, ability in ipairs(ABILITIES) do
        local is_owned = is_sleight_owned(ability.sleight)
        if is_owned and not has_flag(wanted, ability.flag) then
            wanted = wanted + ability.flag
        elseif not is_owned and has_flag(wanted, ability.flag) then
            wanted = wanted - ability.flag
        end
    end
    return wanted
end

local function apply_movement_abilities()
    if not follow_sleights or not world_order.is_sora_story() or ReadLong(journalPointer) == 0 then
        return
    end
    local address = get_variable_address()
    if address == nil then
        return
    end
    local flags = ReadByte(address, true)
    local wanted = get_wanted_flags(flags)
    if wanted ~= flags then
        WriteByte(address, wanted, true)
    end
end

return {
    set_movement_abilities_follow_sleights = set_movement_abilities_follow_sleights,
    apply_movement_abilities = apply_movement_abilities
}
