local log = require("helpers.log")
local memory_values = require("helpers.memory_values")

local MOV_TO_MEMORY_OPCODE = 0xC7
local CARD_MOV_MODRM = 0x47
local SLEIGHT_MOV_MODRM = 0x07
local CARD_FIELD_DISPLACEMENT = 0x04
local SLEIGHT_FIELD_DISPLACEMENT = 0x00
local CARD_DISPLACEMENT_OFFSET = 2
local CARD_ID_OFFSET = 3
local SLEIGHT_ID_OFFSET = 2
local FIRST_CARD = 0x01
local LAST_CARD = 0xFF
local FIRST_SLEIGHT = 0x01
local LAST_SLEIGHT = 0xFF

local ROOM_OF_REWARDS_CHESTS = {
    {world = 1, chest = 1, kind = "card", offset = 0x8A, vanilla = 0x0A},
    {world = 1, chest = 2, kind = "card", offset = 0x7E, vanilla = 0x79},
    {world = 2, chest = 1, kind = "sleight", offset = 0x133, vanilla = 0x2C},
    {world = 2, chest = 2, kind = "card", offset = 0xAF, vanilla = 0x7B},
    {world = 3, chest = 1, kind = "card", offset = 0x163, vanilla = 0x08},
    {world = 3, chest = 2, kind = "card", offset = 0x157, vanilla = 0x14},
    {world = 4, chest = 1, kind = "sleight", offset = 0x20C, vanilla = 0x30},
    {world = 4, chest = 2, kind = "card", offset = 0x188, vanilla = 0x76},
    {world = 5, chest = 1, kind = "sleight", offset = 0x2B4, vanilla = 0x25},
    {world = 5, chest = 2, kind = "card", offset = 0x230, vanilla = 0x78},
    {world = 6, chest = 1, kind = "sleight", offset = 0x35C, vanilla = 0x2D},
    {world = 6, chest = 2, kind = "card", offset = 0x2D8, vanilla = 0x18},
    {world = 7, chest = 1, kind = "sleight", offset = 0x404, vanilla = 0x2A},
    {world = 7, chest = 2, kind = "card", offset = 0x380, vanilla = 0x7A},
    {world = 8, chest = 1, kind = "sleight", offset = 0x4AC, vanilla = 0x1D},
    {world = 8, chest = 2, kind = "card", offset = 0x428, vanilla = 0x15},
    {world = 9, chest = 1, kind = "card", offset = 0x4DC, vanilla = 0x28},
    {world = 9, chest = 2, kind = "card", offset = 0x4D0, vanilla = 0x77},
    {world = 11, chest = 1, kind = "sleight", offset = 0x585, vanilla = 0x46},
    {world = 11, chest = 2, kind = "card", offset = 0x501, vanilla = 0x7C},
    {world = 12, chest = 1, kind = "card", offset = 0x5B2, vanilla = 0x30},
    {world = 12, chest = 2, kind = "card", offset = 0x5A9, vanilla = 0x17},
    {world = 13, chest = 1, kind = "sleight", offset = 0x68B, vanilla = 0x5C},
    {world = 13, chest = 2, kind = "card", offset = 0x5D7, vanilla = 0x13}
}

local BOUNTY_CHESTS = {
    {world = 1, chest = 1, kind = "card", offset = 0xD1, vanilla = 0x16},
    {world = 2, chest = 1, kind = "card", offset = 0xE5, vanilla = 0x1E},
    {world = 3, chest = 1, kind = "sleight", offset = 0x171, vanilla = 0x1C},
    {world = 4, chest = 1, kind = "card", offset = 0x184, vanilla = 0x1F},
    {world = 5, chest = 1, kind = "sleight", offset = 0x210, vanilla = 0x1B},
    {world = 6, chest = 1, kind = "sleight", offset = 0x29B, vanilla = 0x31},
    {world = 7, chest = 1, kind = "sleight", offset = 0x3B0, vanilla = 0x28},
    {world = 7, chest = 2, kind = "sleight", offset = 0x32D, vanilla = 0x24},
    {world = 8, chest = 1, kind = "sleight", offset = 0x43B, vanilla = 0x32},
    {world = 9, chest = 1, kind = "sleight", offset = 0x4C6, vanilla = 0x1E},
    {world = 10, chest = 1, kind = "card", offset = 0x4D9, vanilla = 0x07},
    {world = 11, chest = 1, kind = "sleight", offset = 0x59C, vanilla = 0x2B},
    {world = 11, chest = 2, kind = "card", offset = 0x518, vanilla = 0x74},
    {world = 12, chest = 1, kind = "sleight", offset = 0x65E, vanilla = 0x1F},
    {world = 12, chest = 2, kind = "card", offset = 0x5DA, vanilla = 0x75},
    {world = 13, chest = 1, kind = "sleight", offset = 0x74F, vanilla = 0x21},
    {world = 13, chest = 2, kind = "card", offset = 0x6D5, vanilla = 0x0F},
    {world = 13, chest = 3, kind = "card", offset = 0x6A1, vanilla = 0x73}
}

local CLEARED_GAME_CHECKS = {
    {offset = 0x4FE, code = {0x0F, 0x84, 0x51, 0x02, 0x00, 0x00}},
    {offset = 0x512, code = {0x0F, 0x84, 0x3D, 0x02, 0x00, 0x00}},
    {offset = 0x5C0, code = {0x0F, 0x84, 0x8F, 0x01, 0x00, 0x00}},
    {offset = 0x5D4, code = {0x0F, 0x84, 0x7B, 0x01, 0x00, 0x00}},
    {offset = 0x687, code = {0x0F, 0x84, 0xC8, 0x00, 0x00, 0x00}},
    {offset = 0x69B, code = {0x0F, 0x84, 0xB4, 0x00, 0x00, 0x00}},
    {offset = 0x6BB, code = {0x0F, 0x84, 0x94, 0x00, 0x00, 0x00}},
    {offset = 0x6CF, code = {0x0F, 0x84, 0x80, 0x00, 0x00, 0x00}}
}
local NO_OPERATION = 0x90

local ignore_cleared_game = nil
local room_of_rewards_changes = {}
local bounty_changes = {}
local reported_problems = {}

local function report_once(message)
    if reported_problems[message] then
        return
    end
    reported_problems[message] = true
    log.log_debug("chest rewards: " .. message)
end

local function find_chest(chest_list, world_id, chest_number)
    for _, chest in ipairs(chest_list) do
        if chest.world == world_id and chest.chest == chest_number then
            return chest
        end
    end
    return nil
end

local function check_reward(chest, reward, list_name)
    if type(reward) ~= "table" then
        log.log_debug("chest rewards: a reward needs a card or a sleight")
        return false
    end
    if reward.card ~= nil and reward.sleight ~= nil then
        log.log_debug("chest rewards: a reward can be a card or a sleight, not both")
        return false
    end
    if reward.card ~= nil then
        if chest.kind == "sleight" then
            log.log_debug("chest rewards: " .. list_name .. " world " .. chest.world .. " chest " .. chest.chest ..
                " gives a sleight and can not be changed to a card")
            return false
        end
        if not memory_values.is_whole_number(reward.card, FIRST_CARD, LAST_CARD) then
            log.log_debug("chest rewards: card must be a card id from 0x01 to 0xFF")
            return false
        end
        return true
    end
    if reward.sleight ~= nil then
        if not memory_values.is_whole_number(reward.sleight, FIRST_SLEIGHT, LAST_SLEIGHT) then
            log.log_debug("chest rewards: sleight must be a sleight id from 0x01 to 0xFF")
            return false
        end
        return true
    end
    log.log_debug("chest rewards: a reward needs a card or a sleight")
    return false
end

local function set_chest_reward(chest_list, changes, list_name, world_id, chest_number, reward)
    local chest = find_chest(chest_list, world_id, chest_number)
    if chest == nil then
        log.log_debug("chest rewards: " .. list_name .. " has no chest " .. tostring(chest_number) ..
            " in world " .. tostring(world_id))
        return false
    end
    if reward == nil then
        changes[chest] = {}
        if chest.kind == "card" then
            changes[chest].card = chest.vanilla
        else
            changes[chest].sleight = chest.vanilla
        end
        return true
    end
    if not check_reward(chest, reward, list_name) then
        return false
    end
    changes[chest] = reward
    return true
end

local function set_room_of_rewards_reward(world_id, chest_number, reward)
    return set_chest_reward(ROOM_OF_REWARDS_CHESTS, room_of_rewards_changes, "Room of Rewards", world_id,
        chest_number, reward)
end

local function set_bounty_reward(world_id, chest_number, reward)
    return set_chest_reward(BOUNTY_CHESTS, bounty_changes, "bounty", world_id, chest_number, reward)
end

local function is_card_code(address)
    return ReadByte(address) == MOV_TO_MEMORY_OPCODE and ReadByte(address + 1) == CARD_MOV_MODRM
end

local function is_sleight_code(address)
    return ReadByte(address) == MOV_TO_MEMORY_OPCODE and ReadByte(address + 1) == SLEIGHT_MOV_MODRM
end

local function keep_code_byte(address, value)
    if ReadByte(address) ~= value then
        WriteByte(address, value)
    end
end

local function keep_code_int(address, value)
    if ReadInt(address) ~= value then
        WriteInt(address, value)
    end
end

local function read_chest_reward(code_start, chest)
    local address = code_start + chest.offset
    local reward = {}
    if is_sleight_code(address) then
        reward.sleight = ReadInt(address + SLEIGHT_ID_OFFSET)
        return reward
    end
    if not is_card_code(address) then
        return nil
    end
    local id = ReadInt(address + CARD_ID_OFFSET)
    if ReadByte(address + CARD_DISPLACEMENT_OFFSET) == SLEIGHT_FIELD_DISPLACEMENT then
        reward.sleight = id
    else
        reward.card = id
    end
    return reward
end

local function get_room_of_rewards_reward(world_id, chest_number)
    local chest = find_chest(ROOM_OF_REWARDS_CHESTS, world_id, chest_number)
    if chest == nil then
        return nil
    end
    return read_chest_reward(roomOfRewardsChestCode, chest)
end

local function get_bounty_reward(world_id, chest_number)
    local chest = find_chest(BOUNTY_CHESTS, world_id, chest_number)
    if chest == nil then
        return nil
    end
    return read_chest_reward(bountyChestCode, chest)
end

local function write_chest_reward(code_start, chest, reward, list_name)
    local address = code_start + chest.offset
    if chest.kind == "sleight" then
        if not is_sleight_code(address) then
            report_once(list_name .. " world " .. chest.world .. " chest " .. chest.chest ..
                " code is not where it should be")
            return
        end
        keep_code_int(address + SLEIGHT_ID_OFFSET, reward.sleight)
        return
    end
    if not is_card_code(address) then
        report_once(list_name .. " world " .. chest.world .. " chest " .. chest.chest ..
            " code is not where it should be")
        return
    end
    if reward.sleight ~= nil then
        keep_code_byte(address + CARD_DISPLACEMENT_OFFSET, SLEIGHT_FIELD_DISPLACEMENT)
        keep_code_int(address + CARD_ID_OFFSET, reward.sleight)
    else
        keep_code_byte(address + CARD_DISPLACEMENT_OFFSET, CARD_FIELD_DISPLACEMENT)
        keep_code_int(address + CARD_ID_OFFSET, reward.card)
    end
end

local function set_bounties_ignore_clear(ignore)
    if type(ignore) ~= "boolean" then
        log.log_debug("chest rewards: ignore must be true or false")
        return false
    end
    ignore_cleared_game = ignore
    return true
end

local function is_check_vanilla(address, code)
    for index, value in ipairs(code) do
        if ReadByte(address + index - 1) ~= value then
            return false
        end
    end
    return true
end

local function is_check_removed(address, code)
    for index = 1, #code do
        if ReadByte(address + index - 1) ~= NO_OPERATION then
            return false
        end
    end
    return true
end

local function write_check(address, code)
    for index, value in ipairs(code) do
        if ignore_cleared_game then
            keep_code_byte(address + index - 1, NO_OPERATION)
        else
            keep_code_byte(address + index - 1, value)
        end
    end
end

local function apply_cleared_game_checks()
    if ignore_cleared_game == nil then
        return
    end
    for _, check in ipairs(CLEARED_GAME_CHECKS) do
        local address = bountyChestCode + check.offset
        if is_check_vanilla(address, check.code) or is_check_removed(address, check.code) then
            write_check(address, check.code)
        else
            report_once("a cleared game check is not where it should be")
        end
    end
end

local function apply_chest_rewards()
    apply_cleared_game_checks()
    for chest, reward in pairs(room_of_rewards_changes) do
        write_chest_reward(roomOfRewardsChestCode, chest, reward, "Room of Rewards")
    end
    for chest, reward in pairs(bounty_changes) do
        write_chest_reward(bountyChestCode, chest, reward, "bounty")
    end
end

local function copy_chest_list(chest_list)
    local copy = {}
    for _, chest in ipairs(chest_list) do
        copy[#copy + 1] = {world = chest.world, chest = chest.chest, kind = chest.kind, vanilla = chest.vanilla}
    end
    return copy
end

local function get_room_of_rewards_chests()
    return copy_chest_list(ROOM_OF_REWARDS_CHESTS)
end

local function get_bounty_chests()
    return copy_chest_list(BOUNTY_CHESTS)
end

return {
    set_room_of_rewards_reward = set_room_of_rewards_reward,
    set_bounty_reward = set_bounty_reward,
    get_room_of_rewards_reward = get_room_of_rewards_reward,
    get_bounty_reward = get_bounty_reward,
    get_room_of_rewards_chests = get_room_of_rewards_chests,
    get_bounty_chests = get_bounty_chests,
    set_bounties_ignore_clear = set_bounties_ignore_clear,
    apply_chest_rewards = apply_chest_rewards
}
