local LEVEL_UP_SLEIGHT_OFFSETS = {0x00, 0x02, 0x07, 0x09, 0x0E, 0x10, 0x15, 0x17, 0x1C, 0x1E, 0x23, 0x25}
local UNREACHABLE_LEVEL = 0x65

local WORLDS = {
    TRAVERSE_TOWN = 1,
    AGRABAH = 2,
    OLYMPUS_COLISEUM = 3,
    WONDERLAND = 4,
    MONSTRO = 5,
    HALLOWEEN_TOWN = 6,
    ATLANTICA = 7,
    NEVERLAND = 8,
    HOLLOW_BASTION = 9,
    HUNDRED_ACRE_WOOD = 10,
    TWILIGHT_TOWN = 11,
    DESTINY_ISLANDS = 12,
    CASTLE_OBLIVION = 13
}

local function get_level_up_sleight_count()
    return #LEVEL_UP_SLEIGHT_OFFSETS
end

local function get_level_up_sleight(slot)
    local level_address = levelUpSleightTable + LEVEL_UP_SLEIGHT_OFFSETS[slot]
    local sleight_address = level_address + 1
    return ReadByte(level_address), ReadByte(sleight_address)
end

local function set_level_up_sleight(slot, level, sleight)
    local level_address = levelUpSleightTable + LEVEL_UP_SLEIGHT_OFFSETS[slot]
    local sleight_address = level_address + 1
    WriteByte(level_address, level)
    WriteByte(sleight_address, sleight)
end

local function disable_level_up_sleights()
    for slot = 1, #LEVEL_UP_SLEIGHT_OFFSETS do
        local level_address = levelUpSleightTable + LEVEL_UP_SLEIGHT_OFFSETS[slot]
        WriteByte(level_address, UNREACHABLE_LEVEL)
    end
end

local function get_boss_reward_record_address(record_number)
    return bossRewardTable + ((record_number - 1) * BOSS_REWARD_RECORD_SIZE)
end

local function get_boss_reward(record_number)
    local record_address = get_boss_reward_record_address(record_number)
    local reward = {}
    reward.boss_id = ReadInt(record_address + BOSS_REWARD_BOSS_ID)
    reward.card_type = ReadInt(record_address + BOSS_REWARD_CARD_TYPE)
    reward.card_number = ReadInt(record_address + BOSS_REWARD_CARD_NUMBER)
    return reward
end

local function set_boss_reward(record_number, card_type, card_number)
    local record_address = get_boss_reward_record_address(record_number)
    WriteInt(record_address + BOSS_REWARD_CARD_TYPE, card_type)
    WriteInt(record_address + BOSS_REWARD_CARD_NUMBER, card_number)
end

local function get_world_select_story_row(story)
    if story == "riku" then
        return 0
    end
    return 1
end

local function get_world_select_group(floor_group)
    if floor_group == "floors_2_to_6" then
        return worldSelectFloors2To6Table, WORLD_SELECT_FLOORS_2_TO_6_ROW_SIZE
    end
    if floor_group == "floors_7_to_10" then
        return worldSelectFloors7To10Table, WORLD_SELECT_FLOORS_7_TO_10_ROW_SIZE
    end
    if floor_group == "floors_11_to_13" then
        return worldSelectFloors11To13Table, WORLD_SELECT_FLOORS_11_TO_13_ROW_SIZE
    end
    return nil, 0
end

local function get_world_select_entry_address(floor_group, story, slot)
    local table_address, row_size = get_world_select_group(floor_group)
    if table_address == nil then
        return nil
    end
    if slot < 1 or slot > row_size then
        return nil
    end
    local row = get_world_select_story_row(story)
    local entry_index = (row * row_size) + (slot - 1)
    return table_address + (entry_index * WORLD_SELECT_ENTRY_SIZE)
end

local function get_world_select_card(floor_group, story, slot)
    local entry_address = get_world_select_entry_address(floor_group, story, slot)
    if entry_address == nil then
        return nil
    end
    return ReadShort(entry_address)
end

local function set_world_select_card(floor_group, story, slot, world_id)
    local entry_address = get_world_select_entry_address(floor_group, story, slot)
    if entry_address == nil then
        return false
    end
    WriteShort(entry_address, world_id)
    return true
end

local function get_world_select_cards(floor_group, story)
    local _, row_size = get_world_select_group(floor_group)
    local world_ids = {}
    for slot = 1, row_size do
        world_ids[slot] = get_world_select_card(floor_group, story, slot)
    end
    return world_ids
end

local function get_exp_gem_divisor_address(gem_number)
    return expGemTable + ((gem_number - 1) * EXP_GEM_ENTRY_SIZE) + EXP_GEM_DIVISOR
end

local function get_exp_gem_divisor(gem_number)
    return ReadInt(get_exp_gem_divisor_address(gem_number))
end

local function set_exp_gem_divisor(gem_number, divisor)
    WriteInt(get_exp_gem_divisor_address(gem_number), divisor)
end

return {
    WORLDS = WORLDS,
    get_level_up_sleight_count = get_level_up_sleight_count,
    get_level_up_sleight = get_level_up_sleight,
    set_level_up_sleight = set_level_up_sleight,
    disable_level_up_sleights = disable_level_up_sleights,
    get_boss_reward = get_boss_reward,
    set_boss_reward = set_boss_reward,
    get_world_select_card = get_world_select_card,
    set_world_select_card = set_world_select_card,
    get_world_select_cards = get_world_select_cards,
    get_exp_gem_divisor = get_exp_gem_divisor,
    set_exp_gem_divisor = set_exp_gem_divisor
}
