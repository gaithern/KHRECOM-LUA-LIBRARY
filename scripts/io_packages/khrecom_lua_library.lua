local bits = require("helpers.bits")
local cards = require("modules.cards")
local exe_tables = require("modules.exe_tables")
local world_select = require("modules.world_select")

local SLEIGHTS_PER_BYTE = 4
local SLEIGHT_BIT_VALUES = {2, 8, 32, 128}
local KO_CONTROL_STATE = 29
local KO_DEATH_FLAG_BIT = 3
local KO_DEATH_FLAG_VALUE = 4
local KO_DEATH_STATE = 7

local function get_journal_address(offset)
    return GetPointer(journalPointer, offset)
end

local function get_floor_data_address(offset)
    return GetPointer(floorDataPointer, offset)
end

local function get_event_data_address(offset)
    return GetPointer(eventDataPointer, offset)
end

local function get_player_data_address(offset)
    return GetPointer(playerDataPointer, offset)
end

local function get_time_played_address()
    local first_pointer = GetPointer(timePlayedPointer, TIME_PLAYED_FIRST_OFFSET)
    return GetPointer(first_pointer, TIME_PLAYED_SECOND_OFFSET, true)
end

local function get_deck_address(deck_number)
    local deck_offset = PLAYER_DATA_DECK_1 + ((deck_number - 1) * PLAYER_DATA_DECK_SIZE)
    return get_player_data_address(deck_offset)
end

local function get_sleight_count()
    return JOURNAL_SLEIGHTS_OBTAINED_SIZE * SLEIGHTS_PER_BYTE
end

local function get_current_floor()
    return ReadByte(currentFloor)
end

local function get_current_room()
    return ReadShort(currentRoom)
end

local function get_current_world()
    return ReadByte(currentWorld)
end

local function get_time_played()
    return ReadInt(get_time_played_address(), true)
end

local function get_journal_cards_found()
    return ReadArray(get_journal_address(JOURNAL_CARDS_FOUND), JOURNAL_CARDS_FOUND_SIZE, true)
end

local function get_heartless_defeated()
    local raw_bytes = ReadArray(get_journal_address(JOURNAL_HEARTLESS_DEFEATED), JOURNAL_HEARTLESS_DEFEATED_COUNT * 2, true)
    local defeat_counts = {}
    for heartless_number = 1, JOURNAL_HEARTLESS_DEFEATED_COUNT do
        local low_byte = raw_bytes[(heartless_number * 2) - 1]
        local high_byte = raw_bytes[heartless_number * 2]
        defeat_counts[heartless_number] = low_byte + (high_byte * 256)
    end
    return defeat_counts
end

local function get_rooms_opened()
    return ReadArray(get_floor_data_address(FLOOR_DATA_ROOMS_OPENED), FLOOR_DATA_ROOMS_OPENED_SIZE, true)
end

local function get_world_assignments()
    return ReadArray(get_floor_data_address(FLOOR_DATA_WORLD_ASSIGNMENTS), FLOOR_DATA_WORLD_ASSIGNMENTS_SIZE, true)
end

local function get_friend_cards()
    return ReadArray(get_journal_address(JOURNAL_FRIEND_CARDS), JOURNAL_FRIEND_CARDS_SIZE, true)
end

local function get_rewards_bounties()
    return ReadArray(get_event_data_address(EVENT_DATA_REWARDS_BOUNTIES), EVENT_DATA_REWARDS_BOUNTIES_SIZE, true)
end

local function get_minigames_cleared()
    return ReadArray(get_journal_address(JOURNAL_MINIGAMES_CLEARED), JOURNAL_MINIGAMES_CLEARED_SIZE, true)
end

local function get_world_journal_entries()
    return ReadArray(get_journal_address(JOURNAL_WORLD_ENTRIES), JOURNAL_WORLD_ENTRIES_SIZE, true)
end

local function get_exit_hall_events()
    return ReadArray(get_event_data_address(EVENT_DATA_EXIT_HALL_EVENTS), EVENT_DATA_EXIT_HALL_EVENTS_SIZE, true)
end

local function get_story_progress()
    return ReadByte(get_player_data_address(PLAYER_DATA_STORY_PROGRESS), true)
end

local function get_soras_level()
    return ReadInt(get_player_data_address(PLAYER_DATA_SORA_LEVEL), true)
end

local function get_attack_power()
    return ReadInt(GetPointer(attackPowerPointer, ATTACK_POWER), true)
end

local function get_journal_world_value()
    return ReadShort(get_journal_address(JOURNAL_WORLD_VALUE), true)
end

local function is_piglet_found()
    return ReadByte(get_journal_address(JOURNAL_PIGLET_FOUND), true) > 0
end

local function get_battle_card_inventory()
    return ReadArray(get_player_data_address(PLAYER_DATA_BATTLE_CARDS), PLAYER_DATA_BATTLE_CARDS_SIZE, true)
end

local function get_enemy_card_inventory()
    return ReadArray(get_player_data_address(PLAYER_DATA_ENEMY_CARDS), PLAYER_DATA_ENEMY_CARDS_SIZE, true)
end

local function get_map_card_inventory()
    return ReadArray(get_player_data_address(PLAYER_DATA_MAP_CARDS), PLAYER_DATA_MAP_CARDS_SIZE, true)
end

local function get_deck(deck_number)
    local deck_byte_count = PLAYER_DATA_DECK_CARD_COUNT * 4
    return ReadArray(get_deck_address(deck_number), deck_byte_count, true)
end

local function get_gold_map_cards()
    return ReadArray(GetPointer(goldMapCardsPointer, GOLD_MAP_CARDS), GOLD_MAP_CARDS_SIZE, true)
end

local function get_watched_days()
    return ReadByte(watchedDaysFlag)
end

local function is_sora_loaded()
    return ReadLong(soraControlPointer) ~= 0
end

local function get_sora_hp()
    if not is_sora_loaded() then
        return nil
    end
    return ReadInt(GetPointer(soraControlPointer, SORA_CONTROL_HP), true)
end

local function set_battle_card_inventory(inventory)
    WriteArray(get_player_data_address(PLAYER_DATA_BATTLE_CARDS), inventory, true)
end

local function set_enemy_card_inventory(inventory)
    WriteArray(get_player_data_address(PLAYER_DATA_ENEMY_CARDS), inventory, true)
end

local function set_map_card_inventory(inventory)
    WriteArray(get_player_data_address(PLAYER_DATA_MAP_CARDS), inventory, true)
end

local function set_deck(deck_number, deck_bytes)
    WriteArray(get_deck_address(deck_number), deck_bytes, true)
end

local function set_sleights_obtained(sleight_flags)
    local sleight_bytes = {}
    for byte_number = 1, JOURNAL_SLEIGHTS_OBTAINED_SIZE do
        local sleight_byte = 0
        for position = 1, SLEIGHTS_PER_BYTE do
            local sleight_number = ((byte_number - 1) * SLEIGHTS_PER_BYTE) + position
            if sleight_flags[sleight_number] == 1 then
                sleight_byte = sleight_byte + SLEIGHT_BIT_VALUES[position]
            end
        end
        sleight_bytes[byte_number] = sleight_byte
    end
    WriteArray(get_journal_address(JOURNAL_SLEIGHTS_OBTAINED), sleight_bytes, true)
end

local function set_gold_map_cards(gold_map_cards)
    WriteArray(GetPointer(goldMapCardsPointer, GOLD_MAP_CARDS), gold_map_cards, true)
end

local function set_world_assignments(world_assignments)
    WriteArray(get_floor_data_address(FLOOR_DATA_WORLD_ASSIGNMENTS), world_assignments, true)
end

local function set_world_journal_entries(world_journal_entries)
    WriteArray(get_journal_address(JOURNAL_WORLD_ENTRIES), world_journal_entries, true)
end

local function set_exit_hall_events(exit_hall_events)
    WriteArray(get_event_data_address(EVENT_DATA_EXIT_HALL_EVENTS), exit_hall_events, true)
end

local function set_story_progress(story_progress)
    WriteByte(get_player_data_address(PLAYER_DATA_STORY_PROGRESS), story_progress, true)
end

local function set_attack_power(attack_power)
    WriteInt(GetPointer(attackPowerPointer, ATTACK_POWER), attack_power, true)
end

local function set_journal_card_found(card_number, value)
    local card_address = get_journal_address(JOURNAL_CARDS_FOUND) + (card_number - 1)
    WriteByte(card_address, value, true)
end

local function set_friend_flag(value)
    local friend_flag_address = get_time_played_address() + TIME_PLAYED_FRIEND_FLAG
    WriteByte(friend_flag_address, value, true)
end

local function set_watched_days(value)
    WriteByte(watchedDaysFlag, value)
end

local function ko_sora()
    if ReadLong(soraControlPointer) == 0 then
        return false
    end
    if ReadLong(soraDeathPointer) == 0 then
        return false
    end
    local control_address = GetPointer(soraControlPointer)
    local death_address = GetPointer(soraDeathPointer)
    local death_flags = ReadInt(death_address + SORA_DEATH_FLAGS, true)
    local death_flag_bits = bits.byte_to_bits(death_flags % 256)
    if death_flag_bits[KO_DEATH_FLAG_BIT] == 1 then
        return false
    end
    WriteInt(control_address + SORA_CONTROL_STATE, KO_CONTROL_STATE, true)
    WriteInt(death_address + SORA_DEATH_FLAGS, death_flags + KO_DEATH_FLAG_VALUE, true)
    WriteInt(death_address + SORA_DEATH_STATE, KO_DEATH_STATE, true)
    return true
end

return {
    byte_to_bits = bits.byte_to_bits,
    bits_to_byte = bits.bits_to_byte,
    ReadBits = bits.ReadBits,
    ReadBit = bits.ReadBit,
    WriteBit = bits.WriteBit,
    contains = bits.contains,
    get_sleight_count = get_sleight_count,
    get_current_floor = get_current_floor,
    get_current_room = get_current_room,
    get_current_world = get_current_world,
    get_time_played = get_time_played,
    get_journal_cards_found = get_journal_cards_found,
    get_heartless_defeated = get_heartless_defeated,
    get_rooms_opened = get_rooms_opened,
    get_world_assignments = get_world_assignments,
    get_friend_cards = get_friend_cards,
    get_rewards_bounties = get_rewards_bounties,
    get_minigames_cleared = get_minigames_cleared,
    get_world_journal_entries = get_world_journal_entries,
    get_exit_hall_events = get_exit_hall_events,
    get_story_progress = get_story_progress,
    get_soras_level = get_soras_level,
    get_attack_power = get_attack_power,
    get_journal_world_value = get_journal_world_value,
    is_piglet_found = is_piglet_found,
    get_battle_card_inventory = get_battle_card_inventory,
    get_enemy_card_inventory = get_enemy_card_inventory,
    get_map_card_inventory = get_map_card_inventory,
    get_deck = get_deck,
    get_gold_map_cards = get_gold_map_cards,
    get_watched_days = get_watched_days,
    is_sora_loaded = is_sora_loaded,
    get_sora_hp = get_sora_hp,
    set_battle_card_inventory = set_battle_card_inventory,
    set_enemy_card_inventory = set_enemy_card_inventory,
    set_map_card_inventory = set_map_card_inventory,
    set_deck = set_deck,
    set_sleights_obtained = set_sleights_obtained,
    set_gold_map_cards = set_gold_map_cards,
    set_world_assignments = set_world_assignments,
    set_world_journal_entries = set_world_journal_entries,
    set_exit_hall_events = set_exit_hall_events,
    set_story_progress = set_story_progress,
    set_attack_power = set_attack_power,
    set_journal_card_found = set_journal_card_found,
    set_friend_flag = set_friend_flag,
    set_watched_days = set_watched_days,
    ko_sora = ko_sora,
    get_battle_card_slot = cards.get_battle_card_slot,
    get_empty_battle_card_inventory = cards.get_empty_battle_card_inventory,
    add_battle_card = cards.add_battle_card,
    build_deck_bytes = cards.build_deck_bytes,
    get_level_up_sleight_count = exe_tables.get_level_up_sleight_count,
    get_level_up_sleight = exe_tables.get_level_up_sleight,
    set_level_up_sleight = exe_tables.set_level_up_sleight,
    disable_level_up_sleights = exe_tables.disable_level_up_sleights,
    get_boss_reward = exe_tables.get_boss_reward,
    set_boss_reward = exe_tables.set_boss_reward,
    get_world_select_card = exe_tables.get_world_select_card,
    set_world_select_card = exe_tables.set_world_select_card,
    get_world_select_cards = exe_tables.get_world_select_cards,
    set_world_select_handler = world_select.set_world_select_handler,
    get_world_select_choices = world_select.get_world_select_choices,
    get_exp_gem_divisor = exe_tables.get_exp_gem_divisor,
    set_exp_gem_divisor = exe_tables.set_exp_gem_divisor
}
