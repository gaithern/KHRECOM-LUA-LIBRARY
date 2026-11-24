local log = require("helpers.log")
local memory_values = require("helpers.memory_values")
local loaded_files = require("modules.loaded_files")

local FIRST_WORLD = 1
local LAST_WORLD = 13
local FIRST_BATTLE_CARD = 0x01
local LAST_BATTLE_CARD = 0x30
local FIRST_DROP_MAP_CARD = 0xA1
local LAST_DROP_MAP_CARD = 0xB9
local MAX_BATTLE_CARDS = 44
local MAX_MAP_CARDS = 24
local WEIGHT_TOTAL = 100
local MAX_RATE = 100

local COUNT_OFFSET = 0x06
local FIRST_ENTRY_OFFSET = 0x08
local ENTRY_SIZE = 4
local ENTRY_WEIGHT_OFFSET = 2
local COUNT_SIZE = 2
local MAP_CARD_DROP_FILE = "mapcarddrop.bin"

local BATTLE_LIST_BUFFER_OFFSET = 0x00
local MAP_LIST_BUFFER_OFFSET = 0x164

local READ_FROM_FILE_CODE = {0x48, 0x85, 0xC0, 0x74, 0x06, 0x48, 0x8B, 0x58, 0x08}
local LOAD_BUFFER_INSTRUCTION = {0x48, 0x8D, 0x1D}
local LOAD_BUFFER_SIZE = 7
local DISTANCE_SIZE = 4
local SKIP_FILE_READ_CODE = {0xEB, 0x05}

local STANDARD_CARD_TABLE_SIZE = 0x2A
local STANDARD_CARD = 0
local SPECIAL_CARD = 1
local STANDARD_CARDS = {
    [0x01] = true, [0x02] = true, [0x03] = true, [0x04] = true, [0x05] = true, [0x06] = true,
    [0x09] = true, [0x0B] = true, [0x0C] = true, [0x1B] = true, [0x1D] = true, [0x2A] = true
}

local world_odds = {}
local odds_applied = false
local reported_problems = {}

local function report_once(message)
    if reported_problems[message] then
        return
    end
    reported_problems[message] = true
    log.log_debug("card odds: " .. message)
end

local function check_odds_list(entries, first_card, last_card, max_cards, list_name)
    if type(entries) ~= "table" or #entries == 0 or #entries > max_cards then
        log.log_debug("card odds: " .. list_name .. " must be a list of 1 to " .. max_cards .. " cards")
        return false
    end
    local total = 0
    for index, entry in ipairs(entries) do
        if type(entry) ~= "table" then
            log.log_debug("card odds: " .. list_name .. " entry " .. index .. " must be a table")
            return false
        end
        if not memory_values.is_whole_number(entry.card, first_card, last_card) then
            log.log_debug("card odds: " .. list_name .. " entry " .. index .. " has a bad card id")
            return false
        end
        if not memory_values.is_whole_number(entry.weight, 0, WEIGHT_TOTAL) then
            log.log_debug("card odds: " .. list_name .. " entry " .. index .. " needs a weight from 0 to 100")
            return false
        end
        total = total + entry.weight
    end
    if total ~= WEIGHT_TOTAL then
        log.log_debug("card odds: " .. list_name .. " weights must add up to 100, not " .. total)
        return false
    end
    return true
end

local function check_rate(rate, name)
    if rate == nil then
        return true
    end
    if not memory_values.is_whole_number(rate, 0, MAX_RATE) then
        log.log_debug("card odds: " .. name .. " must be from 0 to 100")
        return false
    end
    return true
end

local function set_world_card_odds(world_id, odds)
    if not memory_values.is_whole_number(world_id, FIRST_WORLD, LAST_WORLD) then
        log.log_debug("card odds: world id must be from 1 to 13")
        return false
    end
    if odds == nil then
        world_odds[world_id] = nil
        return true
    end
    if type(odds) ~= "table" then
        log.log_debug("card odds: odds must be a table")
        return false
    end
    local has_chest_cards = odds.chest_cards ~= nil
    local has_object_cards = odds.object_cards ~= nil
    if has_chest_cards ~= has_object_cards then
        log.log_debug("card odds: chest_cards and object_cards must be given together")
        return false
    end
    if has_chest_cards then
        if not check_odds_list(odds.chest_cards, FIRST_BATTLE_CARD, LAST_BATTLE_CARD, MAX_BATTLE_CARDS, "chest_cards") then
            return false
        end
        if not check_odds_list(odds.object_cards, FIRST_BATTLE_CARD, LAST_BATTLE_CARD, MAX_BATTLE_CARDS, "object_cards") then
            return false
        end
    end
    if odds.map_cards ~= nil then
        if not check_odds_list(odds.map_cards, FIRST_DROP_MAP_CARD, LAST_DROP_MAP_CARD, MAX_MAP_CARDS, "map_cards") then
            return false
        end
    end
    if not check_rate(odds.random_joker_rate, "random_joker_rate") then
        return false
    end
    if not check_rate(odds.key_to_rewards_rate, "key_to_rewards_rate") then
        return false
    end
    world_odds[world_id] = odds
    return true
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

local function get_distance_bytes(distance)
    local bytes = {}
    local remaining = distance
    for index = 1, DISTANCE_SIZE do
        bytes[index] = remaining % 256
        remaining = math.floor(remaining / 256)
    end
    return bytes
end

local function add_bytes(bytes, more_bytes)
    for _, value in ipairs(more_bytes) do
        bytes[#bytes + 1] = value
    end
end

local function get_read_from_buffer_code(site, buffer)
    local code = {}
    add_bytes(code, LOAD_BUFFER_INSTRUCTION)
    add_bytes(code, get_distance_bytes(buffer - (site + LOAD_BUFFER_SIZE)))
    add_bytes(code, SKIP_FILE_READ_CODE)
    return code
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
        keep_exe_byte(address + index - 1, value)
    end
end

local function is_read_site_known(site, buffer)
    if is_code_at(site, READ_FROM_FILE_CODE) then
        return true
    end
    return is_code_at(site, get_read_from_buffer_code(site, buffer))
end

local function set_read_site(site, buffer, use_buffer, site_name)
    if not is_read_site_known(site, buffer) then
        report_once(site_name .. " code is not where it should be")
        return false
    end
    if use_buffer then
        write_code(site, get_read_from_buffer_code(site, buffer))
    else
        write_code(site, READ_FROM_FILE_CODE)
    end
    return true
end

local function write_odds_list(count_address, entries, first_card)
    keep_exe_short(count_address, #entries)
    local entry_address = count_address + COUNT_SIZE
    for _, entry in ipairs(entries) do
        keep_exe_short(entry_address, entry.card - first_card)
        keep_exe_short(entry_address + ENTRY_WEIGHT_OFFSET, entry.weight)
        entry_address = entry_address + ENTRY_SIZE
    end
    return entry_address
end

local function write_battle_lists(buffer, odds)
    local chest_count_address = write_odds_list(buffer + COUNT_OFFSET, odds.object_cards, FIRST_BATTLE_CARD)
    write_odds_list(chest_count_address, odds.chest_cards, FIRST_BATTLE_CARD)
end

local function read_file_rates(file_data)
    local count = memory_values.read_signed_short(file_data + COUNT_OFFSET)
    local rates_address = file_data + FIRST_ENTRY_OFFSET + count * ENTRY_SIZE
    local rates = {}
    rates.random_joker_rate = memory_values.read_signed_short(rates_address)
    rates.key_to_rewards_rate = memory_values.read_signed_short(rates_address + 2)
    return rates
end

local function write_map_list(buffer, odds, file_data)
    local rates = read_file_rates(file_data)
    if odds.random_joker_rate ~= nil then
        rates.random_joker_rate = odds.random_joker_rate
    end
    if odds.key_to_rewards_rate ~= nil then
        rates.key_to_rewards_rate = odds.key_to_rewards_rate
    end
    local rates_address = write_odds_list(buffer + COUNT_OFFSET, odds.map_cards, FIRST_DROP_MAP_CARD)
    keep_exe_short(rates_address, rates.random_joker_rate)
    keep_exe_short(rates_address + 2, rates.key_to_rewards_rate)
end

local function is_standard_card_table()
    for index = 0, STANDARD_CARD_TABLE_SIZE - 1 do
        local value = ReadByte(standardDropCardTable + index)
        local is_standard = STANDARD_CARDS[index + 1] == true
        if is_standard and value ~= STANDARD_CARD and value ~= SPECIAL_CARD then
            return false
        end
        if not is_standard and value ~= SPECIAL_CARD then
            return false
        end
    end
    return true
end

local function set_one_roll(use_one_roll)
    if not is_standard_card_table() then
        report_once("the standard card table is not where it should be")
        return false
    end
    local wanted = STANDARD_CARD
    if use_one_roll then
        wanted = SPECIAL_CARD
    end
    for card_id in pairs(STANDARD_CARDS) do
        keep_exe_byte(standardDropCardTable + card_id - 1, wanted)
    end
    return true
end

local function get_current_odds()
    local world_id = loaded_files.find_loaded_drop_world()
    if world_id == nil then
        return nil
    end
    return world_odds[world_id]
end

local function apply_battle_odds(odds)
    local buffer = cardOddsBuffer + BATTLE_LIST_BUFFER_OFFSET
    local use_buffer = odds ~= nil and odds.chest_cards ~= nil
    if use_buffer then
        if not is_read_site_known(battleCardListReadCode, buffer) or not is_standard_card_table() then
            report_once("the battle card roll code is not where it should be")
            return
        end
        write_battle_lists(buffer, odds)
    end
    if set_read_site(battleCardListReadCode, buffer, use_buffer, "battle card list") then
        set_one_roll(use_buffer)
    end
end

local function apply_map_odds(odds, file_map)
    local buffer = cardOddsBuffer + MAP_LIST_BUFFER_OFFSET
    local file_data = file_map[MAP_CARD_DROP_FILE]
    local use_buffer = odds ~= nil and odds.map_cards ~= nil and file_data ~= nil
    if use_buffer then
        if not is_read_site_known(mapCardListReadCode, buffer) then
            report_once("the map card list code is not where it should be")
            return
        end
        write_map_list(buffer, odds, file_data)
    end
    set_read_site(mapCardListReadCode, buffer, use_buffer, "map card list")
end

local function has_any_odds()
    return next(world_odds) ~= nil
end

local function apply_card_odds(file_map)
    if not has_any_odds() and not odds_applied then
        return
    end
    odds_applied = true
    local odds = get_current_odds()
    apply_battle_odds(odds)
    apply_map_odds(odds, file_map)
end

return {
    set_world_card_odds = set_world_card_odds,
    apply_card_odds = apply_card_odds
}
