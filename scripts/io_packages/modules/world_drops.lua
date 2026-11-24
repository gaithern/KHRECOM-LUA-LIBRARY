local log = require("helpers.log")
local memory_values = require("helpers.memory_values")
local loaded_files = require("modules.loaded_files")

local ENTRY_SIZE = 4
local ENTRY_WEIGHT_OFFSET = 2
local FILE_FIRST_COUNT_OFFSET = 6
local FILE_FIRST_ENTRY_OFFSET = 8
local VALUE_WEIGHT_COUNT = 10
local VALUE_WEIGHTS_FILE_OFFSET = 6
local FIRST_BATTLE_CARD = 0x01
local LAST_BATTLE_CARD = 0x7F
local FIRST_DROP_MAP_CARD = 0xA1
local LAST_DROP_MAP_CARD = 0xB8
local MAX_WEIGHT = 100
local MAX_RATE = 100
local FIRST_WORLD = 1
local LAST_WORLD = 13

local OBJECT_ODDS_FIRST_ENTRY_OFFSET = 2
local OBJECT_ODDS_ENTRY_SIZE = 14
local OBJECT_ODDS_CARD_CHANCE_OFFSET = 0xB

local ROOM_CAP_FILE_OFFSET = 0x1A
local ROOM_CAP_PAIR_COUNT = 28
local ROOM_CAP_PAIR_SIZE = 4
local ROOM_CAP_VALUE_OFFSET = 2
local MAX_ROOM_CAP = 99

local ATTACK_CARD_DROP_FILE = "atkcarddrop.bin"
local MAP_CARD_DROP_FILE = "mapcarddrop.bin"
local MAP_CARD_COM_FILE = "mapcardcom.bin"
local GIM_COM_FILE = "gimcom.bin"
local GIM_PROB_FILE = "gimprob.bin"

local world_settings = {}
local chest_value_weights = nil
local object_card_chance = nil
local object_card_room_cap = nil
local reported_problems = {}

local function report_once(message)
    if reported_problems[message] then
        return
    end
    reported_problems[message] = true
    log.log_debug("world drops: " .. message)
end

local function check_card_entries(entries, first_card, last_card, list_name)
    if entries == nil then
        return true
    end
    if type(entries) ~= "table" then
        log.log_debug("world drops: " .. list_name .. " must be a list")
        return false
    end
    for index, entry in ipairs(entries) do
        if type(entry) ~= "table" then
            log.log_debug("world drops: " .. list_name .. " entry " .. index .. " must be a table")
            return false
        end
        if not memory_values.is_whole_number(entry.card, first_card, last_card) then
            log.log_debug("world drops: " .. list_name .. " entry " .. index .. " has a bad card id")
            return false
        end
        if not memory_values.is_whole_number(entry.weight, 0, MAX_WEIGHT) then
            log.log_debug("world drops: " .. list_name .. " entry " .. index .. " needs a weight from 0 to 100")
            return false
        end
    end
    return true
end

local function check_value_weights(weights, name)
    if weights == nil then
        return true
    end
    if type(weights) ~= "table" or #weights ~= VALUE_WEIGHT_COUNT then
        log.log_debug("world drops: " .. name .. " needs 10 weights, one for each value 0 to 9")
        return false
    end
    for index = 1, VALUE_WEIGHT_COUNT do
        if not memory_values.is_whole_number(weights[index], 0, MAX_WEIGHT) then
            log.log_debug("world drops: " .. name .. " weight " .. index .. " must be from 0 to 100")
            return false
        end
    end
    return true
end

local function check_rate(rate, name)
    if rate == nil then
        return true
    end
    if not memory_values.is_whole_number(rate, 0, MAX_RATE) then
        log.log_debug("world drops: " .. name .. " must be from 0 to 100")
        return false
    end
    return true
end

local function set_world_drops(world_id, drops)
    if not memory_values.is_whole_number(world_id, FIRST_WORLD, LAST_WORLD) then
        log.log_debug("world drops: world id must be from 1 to 13")
        return false
    end
    if type(drops) ~= "table" then
        log.log_debug("world drops: drops must be a table")
        return false
    end
    if not check_card_entries(drops.chest_cards, FIRST_BATTLE_CARD, LAST_BATTLE_CARD, "chest_cards") then
        return false
    end
    if not check_card_entries(drops.object_cards, FIRST_BATTLE_CARD, LAST_BATTLE_CARD, "object_cards") then
        return false
    end
    if not check_card_entries(drops.map_cards, FIRST_DROP_MAP_CARD, LAST_DROP_MAP_CARD, "map_cards") then
        return false
    end
    if not check_value_weights(drops.map_card_value_weights, "map_card_value_weights") then
        return false
    end
    if not check_rate(drops.random_joker_rate, "random_joker_rate") then
        return false
    end
    if not check_rate(drops.key_to_rewards_rate, "key_to_rewards_rate") then
        return false
    end
    world_settings[world_id] = drops
    return true
end

local function set_chest_card_value_weights(weights)
    if not check_value_weights(weights, "chest card value weights") then
        return false
    end
    chest_value_weights = weights
    return true
end

local function set_object_card_chance(chance)
    if not memory_values.is_whole_number(chance, 0, MAX_RATE) then
        log.log_debug("world drops: object card chance must be from 0 to 100")
        return false
    end
    object_card_chance = chance
    return true
end

local function set_object_card_room_cap(cap)
    if not memory_values.is_whole_number(cap, 0, MAX_ROOM_CAP) then
        log.log_debug("world drops: object card room cap must be from 0 to 99")
        return false
    end
    object_card_room_cap = cap
    return true
end

local function write_room_caps(pairs_address, cap)
    for index = 0, ROOM_CAP_PAIR_COUNT - 1 do
        local pair_address = pairs_address + index * ROOM_CAP_PAIR_SIZE
        memory_values.keep_short(pair_address + ROOM_CAP_VALUE_OFFSET, cap)
    end
end

local function write_entry_list(list_address, slot_count, entries, card_base, list_name)
    if list_address == 0 then
        return
    end
    if #entries > slot_count then
        report_once(list_name .. " has " .. #entries .. " entries but this world only has room for " .. slot_count)
        return
    end
    for slot = 1, slot_count do
        local entry_address = list_address + (slot - 1) * ENTRY_SIZE
        local entry = entries[slot]
        if entry ~= nil then
            memory_values.keep_short(entry_address, entry.card - card_base)
            memory_values.keep_short(entry_address + ENTRY_WEIGHT_OFFSET, entry.weight)
        else
            memory_values.keep_short(entry_address + ENTRY_WEIGHT_OFFSET, 0)
        end
    end
end

local function write_value_weights(address, weights)
    for index = 1, VALUE_WEIGHT_COUNT do
        memory_values.keep_short(address + (index - 1) * 2, weights[index])
    end
end
local function read_attack_card_lists(file_data)
    local lists = {}
    lists.object_count = memory_values.read_signed_short(file_data + FILE_FIRST_COUNT_OFFSET)
    lists.object_address = file_data + FILE_FIRST_ENTRY_OFFSET
    local chest_count_address = lists.object_address + lists.object_count * ENTRY_SIZE
    lists.chest_count = memory_values.read_signed_short(chest_count_address)
    lists.chest_address = chest_count_address + 2
    return lists
end

local function apply_attack_cards(settings, file_data)
    local lists = read_attack_card_lists(file_data)
    if settings.object_cards ~= nil then
        write_entry_list(lists.object_address, lists.object_count, settings.object_cards, FIRST_BATTLE_CARD, "object_cards")
    end
    if settings.chest_cards ~= nil then
        write_entry_list(lists.chest_address, lists.chest_count, settings.chest_cards, FIRST_BATTLE_CARD, "chest_cards")
    end
end

local function apply_map_cards(settings, file_data)
    local map_card_count = memory_values.read_signed_short(file_data + FILE_FIRST_COUNT_OFFSET)
    local list_address = file_data + FILE_FIRST_ENTRY_OFFSET
    local rates_address = list_address + map_card_count * ENTRY_SIZE
    if settings.map_cards ~= nil then
        write_entry_list(list_address, map_card_count, settings.map_cards, FIRST_DROP_MAP_CARD, "map_cards")
    end
    if settings.random_joker_rate ~= nil then
        memory_values.keep_short(rates_address, settings.random_joker_rate)
    end
    if settings.key_to_rewards_rate ~= nil then
        memory_values.keep_short(rates_address + 2, settings.key_to_rewards_rate)
    end
end

local function write_object_card_chances(list_address, entry_count, chance)
    for index = 0, entry_count - 1 do
        local entry_address = list_address + index * OBJECT_ODDS_ENTRY_SIZE
        memory_values.keep_byte(entry_address + OBJECT_ODDS_CARD_CHANCE_OFFSET, chance)
    end
end

local function apply_object_card_chance(file_data)
    local entry_count = memory_values.read_signed_short(file_data)
    local file_list = file_data + OBJECT_ODDS_FIRST_ENTRY_OFFSET
    write_object_card_chances(file_list, entry_count, object_card_chance)
end

local function apply_world_drops(file_map)
    local drop_world = loaded_files.find_loaded_drop_world()
    local settings = nil
    if drop_world ~= nil then
        settings = world_settings[drop_world]
    end
    if object_card_room_cap ~= nil then
        local gim_com = file_map[GIM_COM_FILE]
        if gim_com ~= nil then
            write_room_caps(gim_com + ROOM_CAP_FILE_OFFSET, object_card_room_cap)
        end
    end
    if object_card_chance ~= nil then
        local gim_prob = file_map[GIM_PROB_FILE]
        if gim_prob ~= nil then
            apply_object_card_chance(gim_prob)
        end
    end
    if chest_value_weights ~= nil then
        local gim_com = file_map[GIM_COM_FILE]
        if gim_com ~= nil then
            write_value_weights(gim_com + VALUE_WEIGHTS_FILE_OFFSET, chest_value_weights)
        end
    end
    if settings == nil then
        return
    end
    local attack_card_drop = file_map[ATTACK_CARD_DROP_FILE]
    if attack_card_drop ~= nil and (settings.chest_cards ~= nil or settings.object_cards ~= nil) then
        apply_attack_cards(settings, attack_card_drop)
    end
    local map_card_drop = file_map[MAP_CARD_DROP_FILE]
    if map_card_drop ~= nil then
        apply_map_cards(settings, map_card_drop)
    end
    local map_card_com = file_map[MAP_CARD_COM_FILE]
    if map_card_com ~= nil and settings.map_card_value_weights ~= nil then
        write_value_weights(map_card_com + VALUE_WEIGHTS_FILE_OFFSET, settings.map_card_value_weights)
    end
end

return {
    set_world_drops = set_world_drops,
    set_chest_card_value_weights = set_chest_card_value_weights,
    set_object_card_chance = set_object_card_chance,
    set_object_card_room_cap = set_object_card_room_cap,
    apply_world_drops = apply_world_drops
}
