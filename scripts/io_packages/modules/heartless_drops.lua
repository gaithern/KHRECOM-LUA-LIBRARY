local log = require("helpers.log")
local memory_values = require("helpers.memory_values")
local loaded_files = require("modules.loaded_files")

local ENEMY_PARAMETER_POOL = 21
local DROP_CHANCE_OFFSET = 0x10
local ALWAYS_DROP = 100

local FIRST_ENEMY_CARD = 0x44
local LAST_ENEMY_CARD = 0x7C
local FIRST_REWARD_CARD = 0x01
local FIRST_HEARTLESS_CARD = 0x44
local LAST_HEARTLESS_CARD = 0x62
local DARKBALL_CARD = 0x59
local SOUL_EATER_CARD = 0x12
local LAST_ATTACK_CARD = 0x18
local FIRST_MAGIC_CARD = 0x1A
local LAST_SUMMON_CARD = 0x29
local FIRST_ITEM_CARD = 0x2A
local LAST_ITEM_CARD = 0x30

local MAGIC_COUNTS_OFFSET = 0x1E0
local ITEM_COUNTS_OFFSET = 0x320
local VALUES_PER_CARD = 10

local JOURNAL_FIRST_DROP_FLAGS = 0x7B
local FIRST_DROP_FLAG = 0x80
local FRAMES_TO_PICK_UP = 3600

local HEARTLESS_CARDS = {
    [0] = 0x00, 0x44, 0x45, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x46, 0x4F, 0x4E, 0x55, 0x56, 0x51, 0x4D, 0x5E, 0x5F,
    0x52, 0x53, 0x54, 0x57, 0x58, 0x59, 0x5B, 0x5C, 0x5A, 0x5D, 0x50, 0x61, 0x62, 0x60, 0x44, 0x51, 0x5E, 0x5F, 0x60,
    0x9F, 0x9F
}
local LAST_KIND = 38

local VANILLA_DROP_CHANCES = {
    4, 3, 3, 3, 3, 3, 2, 4, 2, 2, 3, 4, 3, 2, 3, 4, 3, 4, 4, 2, 3, 4, 0, 4, 3, 4, 3, 4, 4, 3, 2, 4, 2, 4, 3, 2
}

local VANILLA_DROP_CODE = {
    0x44, 0x8B, 0xC0, 0xB8, 0x1F, 0x85, 0xEB, 0x51, 0x41, 0xF7, 0xE8, 0xC1, 0xFA, 0x05, 0x8B, 0xCA, 0xC1, 0xE9,
    0x1F, 0x03, 0xD1, 0x6B, 0xCA, 0x64, 0x44, 0x2B, 0xC1, 0x44, 0x3B, 0xC6, 0x7D, 0x12, 0x8B, 0x87, 0xA0, 0x02,
    0x00, 0x00, 0x89, 0x45, 0x07, 0x44, 0x89, 0x7D, 0x0B, 0xE9, 0xD3, 0x00, 0x00, 0x00
}
local ROLL_AND_FIND_KIND_CODE = {
    0x31, 0xD2, 0x6A, 0x64, 0x59, 0xF7, 0xF1, 0x3B, 0xD6, 0x7D, 0x27, 0x8B, 0x87, 0x28, 0x01, 0x00, 0x00, 0x31, 0xD2,
    0xB9, 0x10, 0x27, 0x00, 0x00, 0xF7, 0xF1
}
local LOAD_TABLE_INSTRUCTION = {0x48, 0x8D, 0x0D}
local STORE_KIND_AND_SET_PRIZE_CODE = {
    0x89, 0x51, 0xF8, 0x48, 0x8B, 0x04, 0xD1, 0x48, 0x89, 0x45, 0x07
}
local JUMP_INSTRUCTION = 0xE9
local SPAWN_PRIZE_CODE_OFFSET = 0xFF
local PRIZE_TABLE_OFFSET = 8
local PRIZE_ENTRY_SIZE = 8
local PRIZE_VALUE_OFFSET = 4
local NO_OPERATION = 0x90
local DISTANCE_SIZE = 4
local DISTANCE_RANGE = 4294967296

local HIGHEST_VALUE_WEIGHT = 100

local value_weights = {10, 10, 10, 10, 10, 10, 10, 10, 10, 10}
local rewards = {}
local guarantee_first_drop = false
local pending_drop = nil
local values_picked = {}
local code_applied = false
local reported_problems = {}

local function report_once(message)
    if reported_problems[message] then
        return
    end
    reported_problems[message] = true
    log.log_debug("heartless drops: " .. message)
end

local function is_heartless_card(card_id)
    if not memory_values.is_whole_number(card_id, FIRST_HEARTLESS_CARD, LAST_HEARTLESS_CARD) then
        return false
    end
    return card_id ~= DARKBALL_CARD
end

local function is_reward_card(card_id)
    if not memory_values.is_whole_number(card_id, FIRST_REWARD_CARD, LAST_ENEMY_CARD) then
        return false
    end
    if card_id == DARKBALL_CARD or card_id == SOUL_EATER_CARD then
        return false
    end
    if card_id >= FIRST_ENEMY_CARD then
        return true
    end
    if card_id <= LAST_ATTACK_CARD then
        return true
    end
    return card_id >= FIRST_MAGIC_CARD and card_id <= LAST_ITEM_CARD and card_id ~= 0x21 and card_id ~= 0x22
end

local function set_heartless_reward(heartless_card, reward_card)
    if not is_heartless_card(heartless_card) then
        log.log_debug("heartless drops: heartless_card must be a Heartless enemy card from 0x44 to 0x62, not Darkball")
        return false
    end
    if not is_reward_card(reward_card) then
        log.log_debug("heartless drops: reward_card must be a battle or enemy card Sora can hold")
        return false
    end
    rewards[heartless_card] = reward_card
    return true
end

local function set_heartless_first_drop_guaranteed(guaranteed)
    if type(guaranteed) ~= "boolean" then
        log.log_debug("heartless drops: guaranteed must be true or false")
        return false
    end
    guarantee_first_drop = guaranteed
    return true
end

local function set_heartless_card_value_weights(weights)
    if type(weights) ~= "table" or #weights ~= VALUES_PER_CARD then
        log.log_debug("heartless drops: value weights need 10 numbers, one for each value 0 to 9")
        return false
    end
    local total = 0
    for index = 1, VALUES_PER_CARD do
        if not memory_values.is_whole_number(weights[index], 0, HIGHEST_VALUE_WEIGHT) then
            log.log_debug("heartless drops: value weight " .. index .. " must be from 0 to 100")
            return false
        end
        total = total + weights[index]
    end
    if total == 0 then
        log.log_debug("heartless drops: at least one value weight must be above 0")
        return false
    end
    value_weights = weights
    values_picked = {}
    return true
end

local function get_total_value_weight()
    local total = 0
    for _, weight in ipairs(value_weights) do
        total = total + weight
    end
    return total
end

local function pick_value()
    local remaining = math.random(1, get_total_value_weight())
    for index, weight in ipairs(value_weights) do
        remaining = remaining - weight
        if remaining <= 0 then
            return index - 1
        end
    end
end

local function get_reward(heartless_card)
    if rewards[heartless_card] ~= nil then
        return rewards[heartless_card]
    end
    return heartless_card
end

local function is_game_loaded()
    return ReadLong(journalPointer) ~= 0 and ReadLong(playerDataPointer) ~= 0
end

local function get_flag_address(heartless_card)
    return GetPointer(journalPointer, JOURNAL_FIRST_DROP_FLAGS + heartless_card - FIRST_HEARTLESS_CARD)
end

local function has_first_drop(heartless_card)
    if not is_heartless_card(heartless_card) or not is_game_loaded() then
        return false
    end
    return ReadByte(get_flag_address(heartless_card), true) >= FIRST_DROP_FLAG
end

local function set_first_drop(heartless_card, received)
    if not is_heartless_card(heartless_card) or type(received) ~= "boolean" or not is_game_loaded() then
        return false
    end
    local address = get_flag_address(heartless_card)
    local other_flags = ReadByte(address, true) % FIRST_DROP_FLAG
    if received then
        WriteByte(address, other_flags + FIRST_DROP_FLAG, true)
    else
        WriteByte(address, other_flags, true)
    end
    return true
end

local function is_code_at(address, code)
    for index, value in ipairs(code) do
        if ReadByte(address + index - 1) ~= value then
            return false
        end
    end
    return true
end

local function write_code(address, code)
    for index, value in ipairs(code) do
        if ReadByte(address + index - 1) ~= value then
            WriteByte(address + index - 1, value)
        end
    end
end

local function add_bytes(bytes, more_bytes)
    for _, value in ipairs(more_bytes) do
        bytes[#bytes + 1] = value
    end
end

local function add_distance(bytes, target, code_address)
    local next_instruction = code_address + #bytes + DISTANCE_SIZE
    local remaining = (target - next_instruction) % DISTANCE_RANGE
    for index = 1, DISTANCE_SIZE do
        bytes[#bytes + 1] = remaining % 256
        remaining = math.floor(remaining / 256)
    end
end

local function get_new_drop_code()
    local code = {}
    add_bytes(code, ROLL_AND_FIND_KIND_CODE)
    add_bytes(code, LOAD_TABLE_INSTRUCTION)
    add_distance(code, heartlessDropSignal + PRIZE_TABLE_OFFSET, heartlessDropCode)
    add_bytes(code, STORE_KIND_AND_SET_PRIZE_CODE)
    code[#code + 1] = JUMP_INSTRUCTION
    add_distance(code, heartlessDropCode + SPAWN_PRIZE_CODE_OFFSET, heartlessDropCode)
    while #code < #VANILLA_DROP_CODE do
        code[#code + 1] = NO_OPERATION
    end
    return code
end

local function get_prize_address(kind)
    return heartlessDropSignal + PRIZE_TABLE_OFFSET + kind * PRIZE_ENTRY_SIZE
end

local function write_prize_cards()
    for kind = 0, LAST_KIND do
        local wanted_card = get_reward(HEARTLESS_CARDS[kind])
        if ReadInt(get_prize_address(kind)) ~= wanted_card then
            WriteInt(get_prize_address(kind), wanted_card)
        end
    end
end

local function write_prize_values()
    for kind = 0, LAST_KIND do
        if values_picked[kind] == nil then
            values_picked[kind] = true
            WriteInt(get_prize_address(kind) + PRIZE_VALUE_OFFSET, pick_value())
        end
    end
end

local function apply_code()
    local new_drop_code = get_new_drop_code()
    if is_code_at(heartlessDropCode, new_drop_code) then
        return true
    end
    if not is_code_at(heartlessDropCode, VANILLA_DROP_CODE) then
        report_once("the enemy card drop code is not where it should be")
        return false
    end
    write_code(heartlessDropCode, new_drop_code)
    return true
end

local function get_battle_card_count(card_id)
    local card_offset = (card_id - 1) * VALUES_PER_CARD
    if card_id >= FIRST_MAGIC_CARD and card_id <= LAST_SUMMON_CARD then
        card_offset = MAGIC_COUNTS_OFFSET + (card_id - FIRST_MAGIC_CARD) * VALUES_PER_CARD
    elseif card_id >= FIRST_ITEM_CARD then
        card_offset = ITEM_COUNTS_OFFSET + (card_id - FIRST_ITEM_CARD) * VALUES_PER_CARD
    end
    local address = GetPointer(playerDataPointer, PLAYER_DATA_BATTLE_CARDS + card_offset)
    local count = 0
    for value = 0, VALUES_PER_CARD - 1 do
        count = count + ReadByte(address + value, true)
    end
    return count
end

local function get_card_count(card_id)
    if card_id >= FIRST_ENEMY_CARD then
        return ReadByte(GetPointer(playerDataPointer, PLAYER_DATA_ENEMY_CARDS + card_id - FIRST_ENEMY_CARD), true)
    end
    return get_battle_card_count(card_id)
end

local function read_new_drop()
    local kind = ReadInt(heartlessDropSignal)
    if kind == 0 then
        return
    end
    WriteInt(heartlessDropSignal, 0)
    values_picked[kind] = nil
    local heartless_card = HEARTLESS_CARDS[kind]
    if heartless_card == nil or not is_heartless_card(heartless_card) then
        return
    end
    pending_drop = {}
    pending_drop.heartless_card = heartless_card
    pending_drop.count = get_card_count(get_reward(heartless_card))
    pending_drop.frames_left = FRAMES_TO_PICK_UP
end

local function update_pending_drop()
    if not is_game_loaded() then
        pending_drop = nil
        WriteInt(heartlessDropSignal, 0)
        return
    end
    read_new_drop()
    if pending_drop == nil then
        return
    end
    if get_card_count(get_reward(pending_drop.heartless_card)) > pending_drop.count then
        set_first_drop(pending_drop.heartless_card, true)
        pending_drop = nil
        return
    end
    pending_drop.frames_left = pending_drop.frames_left - 1
    if pending_drop.frames_left <= 0 then
        pending_drop = nil
    end
end

local function get_kind_from_name(name)
    local kind_text = string.match(string.lower(name), "^en(%d%d%d%d)%.epd$")
    if kind_text == nil then
        return nil
    end
    return tonumber(kind_text)
end

local function get_wanted_chance(kind)
    local heartless_card = HEARTLESS_CARDS[kind]
    if guarantee_first_drop and is_heartless_card(heartless_card) and not has_first_drop(heartless_card) then
        return ALWAYS_DROP
    end
    return VANILLA_DROP_CHANCES[kind]
end

local function apply_chances()
    if not is_game_loaded() then
        return
    end
    for _, file in ipairs(loaded_files.list_loaded_files(ENEMY_PARAMETER_POOL)) do
        local kind = get_kind_from_name(file.name)
        if kind ~= nil and file.data ~= 0 and VANILLA_DROP_CHANCES[kind] ~= nil then
            memory_values.keep_int(file.data + DROP_CHANCE_OFFSET, get_wanted_chance(kind))
        end
    end
end

local function apply_heartless_drops(check_everything)
    if next(rewards) == nil and not guarantee_first_drop then
        return
    end
    write_prize_values()
    if check_everything then
        write_prize_cards()
        code_applied = apply_code()
        apply_chances()
    end
    if code_applied then
        update_pending_drop()
    end
end

return {
    set_heartless_reward = set_heartless_reward,
    set_heartless_first_drop_guaranteed = set_heartless_first_drop_guaranteed,
    set_heartless_card_value_weights = set_heartless_card_value_weights,
    has_first_drop = has_first_drop,
    set_first_drop = set_first_drop,
    apply_heartless_drops = apply_heartless_drops
}
