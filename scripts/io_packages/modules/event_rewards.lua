local log = require("helpers.log")
local memory_values = require("helpers.memory_values")
local loaded_files = require("modules.loaded_files")

local ROOM_SCRIPT_POOL = 37
local HEADER_SIZE = 0x40
local SCRIPT_SIZE_OFFSET = 0x1C
local SCRIPT_SIZE_FLAG = 0x80000000
local INSTRUCTION_SIZE = 8
local OPERAND_OFFSET = 4
local SEARCH_STEP = 4
local GIVE_LENGTH = INSTRUCTION_SIZE * 4
local PUSH_OPCODE = 0x1C
local GIVE_OPCODE = 0xAD
local GIVE_CARD_WITH_POPUP = 5
local GIVE_SLEIGHT = 7
local SET_VARIABLE_OPCODE = 0x60
local PUSH_NUMBER_OPCODE = 0x06
local PRIZE_VARIABLES = 224
local PRIZE_CARD_VARIABLE = 3
local PRIZE_VALUE_VARIABLE = 4
local PRIZE_VALUE_OFFSET = INSTRUCTION_SIZE * 5
local PRIZE_LENGTH = INSTRUCTION_SIZE * 9
local MONSTRO_PRIZE_SCRIPT = "wo051051.abc"
local MONSTRO_PRIZE_CARD = 0x26
local MONSTRO_PRIZE_CARD_OFFSET = -0x10E
local MONSTRO_PRIZE_VALUE_OFFSET = -0x107
local STORE_CARD_CODE = {0xC7, 0x45, 0x07}
local STORE_VALUE_CODE = {0xC7, 0x45, 0x0B}
local FIRST_WORLD = 0
local LAST_WORLD = 13
local LAST_ROOM_CODE = 9999
local FIRST_CARD = 0x01
local LAST_CARD = 0xCA
local FIRST_SLEIGHT = 0x01
local LAST_SLEIGHT = 0xFF
local LAST_VALUE = 9

local card_rewards = {}
local sleight_rewards = {}
local patched_scripts = {}
local reported_monstro_code = false

local function get_script_name(world_id, room_code)
    return string.format("wo%02d%04d.abc", world_id, room_code)
end

local function check_place(world_id, room_code)
    if not memory_values.is_whole_number(world_id, FIRST_WORLD, LAST_WORLD) then
        log.log_debug("event rewards: world id must be from 0 to 13")
        return false
    end
    if not memory_values.is_whole_number(room_code, 0, LAST_ROOM_CODE) then
        log.log_debug("event rewards: room code must be from 0 to 9999")
        return false
    end
    return true
end

local function set_event_card_reward(world_id, room_code, original_card, new_card, new_value)
    if not check_place(world_id, room_code) then
        return false
    end
    if not memory_values.is_whole_number(original_card, FIRST_CARD, LAST_CARD) then
        log.log_debug("event rewards: original card must be a card id from 0x01 to 0xCA")
        return false
    end
    if not memory_values.is_whole_number(new_card, FIRST_CARD, LAST_CARD) then
        log.log_debug("event rewards: new card must be a card id from 0x01 to 0xCA")
        return false
    end
    if not memory_values.is_whole_number(new_value, 0, LAST_VALUE) then
        log.log_debug("event rewards: new value must be from 0 to 9")
        return false
    end
    local script_name = get_script_name(world_id, room_code)
    if card_rewards[script_name] == nil then
        card_rewards[script_name] = {}
    end
    local reward = {}
    reward.card = new_card
    reward.value = new_value
    card_rewards[script_name][original_card] = reward
    return true
end

local function set_event_sleight_reward(world_id, room_code, original_sleight, new_sleight)
    if not check_place(world_id, room_code) then
        return false
    end
    if not memory_values.is_whole_number(original_sleight, FIRST_SLEIGHT, LAST_SLEIGHT) then
        log.log_debug("event rewards: original sleight must be a sleight index from 0x01 to 0xFF")
        return false
    end
    if not memory_values.is_whole_number(new_sleight, FIRST_SLEIGHT, LAST_SLEIGHT) then
        log.log_debug("event rewards: new sleight must be a sleight index from 0x01 to 0xFF")
        return false
    end
    local script_name = get_script_name(world_id, room_code)
    if sleight_rewards[script_name] == nil then
        sleight_rewards[script_name] = {}
    end
    sleight_rewards[script_name][original_sleight] = new_sleight
    return true
end

local function is_push_of(address, operand)
    if ReadShort(address, true) ~= PUSH_OPCODE then
        return false
    end
    return ReadInt(address + OPERAND_OFFSET, true) == operand
end

local function is_push(address)
    return ReadShort(address, true) == PUSH_OPCODE
end

local function get_give_kind(address)
    if not is_push(address) then
        return nil
    end
    if not is_push(address + INSTRUCTION_SIZE) or not is_push(address + INSTRUCTION_SIZE * 2) then
        return nil
    end
    if ReadShort(address + INSTRUCTION_SIZE * 3, true) ~= GIVE_OPCODE then
        return nil
    end
    if is_push_of(address, GIVE_CARD_WITH_POPUP) then
        return GIVE_CARD_WITH_POPUP
    end
    if is_push_of(address, GIVE_SLEIGHT) then
        return GIVE_SLEIGHT
    end
    return nil
end

local function is_prize_part(address, variable)
    if not is_push_of(address, PRIZE_VARIABLES) or not is_push(address + INSTRUCTION_SIZE * 2) then
        return false
    end
    local number_address = address + INSTRUCTION_SIZE
    if ReadShort(number_address, true) ~= PUSH_NUMBER_OPCODE then
        return false
    end
    if ReadInt(number_address + OPERAND_OFFSET, true) ~= variable then
        return false
    end
    return ReadShort(address + INSTRUCTION_SIZE * 3, true) == SET_VARIABLE_OPCODE
end

local function is_prize(address)
    if not is_prize_part(address, PRIZE_CARD_VARIABLE) then
        return false
    end
    return is_prize_part(address + PRIZE_VALUE_OFFSET, PRIZE_VALUE_VARIABLE)
end

local function make_prize_give(address)
    local give = {}
    give.kind = GIVE_CARD_WITH_POPUP
    give.id_address = address + INSTRUCTION_SIZE * 2 + OPERAND_OFFSET
    give.value_address = address + PRIZE_VALUE_OFFSET + INSTRUCTION_SIZE * 2 + OPERAND_OFFSET
    give.original_id = ReadInt(give.id_address, true)
    return give
end

local function find_gives(script_data)
    local gives = {}
    local script_size = ReadInt(script_data + SCRIPT_SIZE_OFFSET, true) % SCRIPT_SIZE_FLAG
    local last_address = script_data + HEADER_SIZE + script_size - GIVE_LENGTH
    local address = script_data + HEADER_SIZE
    while address <= last_address do
        local kind = get_give_kind(address)
        if kind ~= nil then
            local give = {}
            give.kind = kind
            give.id_address = address + INSTRUCTION_SIZE + OPERAND_OFFSET
            give.value_address = address + INSTRUCTION_SIZE * 2 + OPERAND_OFFSET
            give.original_id = ReadInt(give.id_address, true)
            gives[#gives + 1] = give
            address = address + GIVE_LENGTH
        elseif address + PRIZE_LENGTH <= last_address + GIVE_LENGTH and is_prize(address) then
            gives[#gives + 1] = make_prize_give(address)
            address = address + PRIZE_LENGTH
        else
            address = address + SEARCH_STEP
        end
    end
    return gives
end

local function write_give(give, script_name)
    if give.kind == GIVE_CARD_WITH_POPUP and card_rewards[script_name] ~= nil then
        local reward = card_rewards[script_name][give.original_id]
        if reward ~= nil then
            memory_values.keep_int(give.id_address, reward.card)
            memory_values.keep_int(give.value_address, reward.value)
        end
    end
    if give.kind == GIVE_SLEIGHT and sleight_rewards[script_name] ~= nil then
        local new_sleight = sleight_rewards[script_name][give.original_id]
        if new_sleight ~= nil then
            memory_values.keep_int(give.id_address, new_sleight)
        end
    end
end

local function apply_script(script_name, script_data)
    local patched = patched_scripts[script_name]
    if patched == nil or patched.data ~= script_data then
        patched = {}
        patched.data = script_data
        patched.gives = find_gives(script_data)
        patched_scripts[script_name] = patched
    end
    for _, give in ipairs(patched.gives) do
        write_give(give, script_name)
    end
end

local function is_code_at(address, code)
    for index, value in ipairs(code) do
        if ReadByte(address + index - 1) ~= value then
            return false
        end
    end
    return true
end

local function write_code_number(address, value)
    if ReadInt(address) ~= value then
        WriteInt(address, value)
    end
end

local function apply_monstro_prize()
    if card_rewards[MONSTRO_PRIZE_SCRIPT] == nil then
        return
    end
    local reward = card_rewards[MONSTRO_PRIZE_SCRIPT][MONSTRO_PRIZE_CARD]
    if reward == nil then
        return
    end
    local card_address = heartlessDropCode + MONSTRO_PRIZE_CARD_OFFSET
    local value_address = heartlessDropCode + MONSTRO_PRIZE_VALUE_OFFSET
    if not is_code_at(card_address, STORE_CARD_CODE) or not is_code_at(value_address, STORE_VALUE_CODE) then
        if not reported_monstro_code then
            reported_monstro_code = true
            log.log_debug("event rewards: the Monstro prize code is not where it should be")
        end
        return
    end
    write_code_number(card_address + #STORE_CARD_CODE, reward.card)
    write_code_number(value_address + #STORE_VALUE_CODE, reward.value)
end

local function apply_event_rewards()
    if next(card_rewards) == nil and next(sleight_rewards) == nil then
        return
    end
    apply_monstro_prize()
    local script_map = loaded_files.get_loaded_file_map(ROOM_SCRIPT_POOL)
    for script_name, script_data in pairs(script_map) do
        if card_rewards[script_name] ~= nil or sleight_rewards[script_name] ~= nil then
            apply_script(script_name, script_data)
        end
    end
end

return {
    set_event_card_reward = set_event_card_reward,
    set_event_sleight_reward = set_event_sleight_reward,
    apply_event_rewards = apply_event_rewards
}
