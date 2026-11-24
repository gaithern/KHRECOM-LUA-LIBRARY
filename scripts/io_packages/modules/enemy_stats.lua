local log = require("helpers.log")
local memory_values = require("helpers.memory_values")
local loaded_files = require("modules.loaded_files")

local ENEMY_PARAMETER_POOL = 21
local ENP_MAGIC = "@ENP"
local CARD_BLOCK_COUNT_OFFSET = 0x44
local STATS_OFFSET = 0xB0
local STATS_ROW_SIZE = 16
local STATS_HP_OFFSET = 0
local STATS_ATTACK_OFFSET = 4
local STATS_EXP_OFFSET = 8
local FLOOR_COUNT = 13
local DECK_COUNTS_OFFSET = 0x184
local CARD_VALUE_COUNT = 10
local MAX_CARDS_PER_VALUE = 20
local FIRST_ENEMY_KIND = 1
local LAST_ENEMY_KIND = 9999
local MAX_MULTIPLIER = 100
local LOWEST_HP = 1
local HIGHEST_STAT = 1000000
local NO_CHANGE = 1

local decks = {}
local kind_multipliers = {}
local floor_stats_by_file = {}
local hp_multiplier = nil
local attack_multiplier = nil
local exp_multiplier = nil
local original_stats = {}
local reported_problems = {}

local function report_once(message)
    if reported_problems[message] then
        return
    end
    reported_problems[message] = true
    log.log_debug("enemy stats: " .. message)
end

local function set_enemy_deck(kind, counts)
    if not memory_values.is_whole_number(kind, FIRST_ENEMY_KIND, LAST_ENEMY_KIND) then
        log.log_debug("enemy stats: enemy kind must be a whole number from 1")
        return false
    end
    if type(counts) ~= "table" or #counts ~= CARD_VALUE_COUNT then
        log.log_debug("enemy stats: a deck needs 10 numbers, how many cards of each value 0 to 9")
        return false
    end
    local total = 0
    for index = 1, CARD_VALUE_COUNT do
        if not memory_values.is_whole_number(counts[index], 0, MAX_CARDS_PER_VALUE) then
            log.log_debug("enemy stats: deck count " .. index .. " must be from 0 to 20")
            return false
        end
        total = total + counts[index]
    end
    if total == 0 then
        log.log_debug("enemy stats: a deck needs at least one card")
        return false
    end
    decks[kind] = counts
    return true
end

local function check_multiplier(multiplier, name)
    if type(multiplier) ~= "number" or multiplier < 0 or multiplier > MAX_MULTIPLIER then
        log.log_debug("enemy stats: " .. name .. " multiplier must be a number from 0 to 100")
        return false
    end
    return true
end

local function set_enemy_hp_multiplier(multiplier)
    if not check_multiplier(multiplier, "HP") then
        return false
    end
    hp_multiplier = multiplier
    return true
end

local function set_enemy_attack_multiplier(multiplier)
    if not check_multiplier(multiplier, "attack") then
        return false
    end
    attack_multiplier = multiplier
    return true
end

local function set_enemy_exp_multiplier(multiplier)
    if not check_multiplier(multiplier, "EXP") then
        return false
    end
    exp_multiplier = multiplier
    return true
end

local function set_enemy_kind_multipliers(kind, multipliers)
    if not memory_values.is_whole_number(kind, FIRST_ENEMY_KIND, LAST_ENEMY_KIND) then
        log.log_debug("enemy stats: enemy kind must be a whole number from 1")
        return false
    end
    if type(multipliers) ~= "table" then
        log.log_debug("enemy stats: multipliers must be a table with hp, attack and exp")
        return false
    end
    if not check_multiplier(multipliers.hp, "HP") or not check_multiplier(multipliers.attack, "attack") then
        return false
    end
    if not check_multiplier(multipliers.exp, "EXP") then
        return false
    end
    kind_multipliers[kind] = multipliers
    return true
end

local function check_floor_stats(floor_stats, floor)
    if type(floor_stats) ~= "table" then
        log.log_debug("enemy stats: floor " .. floor .. " must be a table with hp, attack and exp")
        return false
    end
    if not memory_values.is_whole_number(floor_stats.hp, LOWEST_HP, HIGHEST_STAT) then
        log.log_debug("enemy stats: floor " .. floor .. " needs an HP above 0")
        return false
    end
    if not memory_values.is_whole_number(floor_stats.attack, 0, HIGHEST_STAT) then
        log.log_debug("enemy stats: floor " .. floor .. " needs an attack of 0 or more")
        return false
    end
    if not memory_values.is_whole_number(floor_stats.exp, 0, HIGHEST_STAT) then
        log.log_debug("enemy stats: floor " .. floor .. " needs an EXP of 0 or more")
        return false
    end
    return true
end

local function set_enemy_floor_stats(file_name, floors)
    if type(file_name) ~= "string" or string.match(string.lower(file_name), "^en%d%d%d%d.*%.epd$") == nil then
        log.log_debug("enemy stats: the file name must look like en0118_2.epd")
        return false
    end
    if type(floors) ~= "table" or #floors ~= FLOOR_COUNT then
        log.log_debug("enemy stats: floor stats need 13 floors")
        return false
    end
    for floor = 1, FLOOR_COUNT do
        if not check_floor_stats(floors[floor], floor) then
            return false
        end
    end
    floor_stats_by_file[string.lower(file_name)] = floors
    return true
end

local function combine(first, second)
    if first == nil then
        return second
    end
    if second == nil then
        return first
    end
    return first * second
end

local function read_magic(address)
    local characters = {}
    for index = 0, 3 do
        characters[#characters + 1] = string.char(ReadByte(address + index, true))
    end
    return table.concat(characters)
end

local function get_kind_from_name(name)
    local kind_text = string.match(string.lower(name), "^en(%d%d%d%d)")
    if kind_text == nil then
        return nil
    end
    return tonumber(kind_text)
end

local function remember_original_stats(enp)
    local stats = {}
    for floor = 1, FLOOR_COUNT do
        local row = enp + STATS_OFFSET + (floor - 1) * STATS_ROW_SIZE
        local floor_stats = {}
        floor_stats.hp = ReadInt(row + STATS_HP_OFFSET, true)
        floor_stats.attack = ReadInt(row + STATS_ATTACK_OFFSET, true)
        floor_stats.exp = ReadInt(row + STATS_EXP_OFFSET, true)
        stats[floor] = floor_stats
    end
    return stats
end

local function get_original_stats(file_name, enp)
    local key = string.lower(file_name) .. "@" .. string.format("%X", enp)
    if original_stats[key] == nil then
        original_stats[key] = remember_original_stats(enp)
    end
    return original_stats[key]
end

local function multiply(value, multiplier, lowest)
    local result = math.floor(value * multiplier + 0.5)
    if result < lowest then
        result = lowest
    end
    return result
end

local function apply_stats(enp, file_name, kind)
    local own = kind_multipliers[kind]
    if own == nil then
        own = {}
    end
    local hp = combine(hp_multiplier, own.hp)
    local attack = combine(attack_multiplier, own.attack)
    local exp = combine(exp_multiplier, own.exp)
    local stats = floor_stats_by_file[string.lower(file_name)]
    if hp == nil and attack == nil and exp == nil and stats == nil then
        return
    end
    if stats ~= nil then
        hp = combine(hp, NO_CHANGE)
        attack = combine(attack, NO_CHANGE)
        exp = combine(exp, NO_CHANGE)
    else
        stats = get_original_stats(file_name, enp)
    end
    for floor = 1, FLOOR_COUNT do
        local row = enp + STATS_OFFSET + (floor - 1) * STATS_ROW_SIZE
        if hp ~= nil then
            memory_values.keep_int(row + STATS_HP_OFFSET, multiply(stats[floor].hp, hp, LOWEST_HP))
        end
        if attack ~= nil then
            memory_values.keep_int(row + STATS_ATTACK_OFFSET, multiply(stats[floor].attack, attack, 0))
        end
        if exp ~= nil then
            memory_values.keep_int(row + STATS_EXP_OFFSET, multiply(stats[floor].exp, exp, 0))
        end
    end
end

local function apply_deck(enp, kind)
    local counts = decks[kind]
    if counts == nil then
        return
    end
    if ReadInt(enp + CARD_BLOCK_COUNT_OFFSET, true) < 1 then
        report_once("enemy kind " .. kind .. " has no deck, so its deck can not be changed")
        return
    end
    for index = 1, CARD_VALUE_COUNT do
        memory_values.keep_byte(enp + DECK_COUNTS_OFFSET + index - 1, counts[index])
    end
end

local function apply_enemy_stats()
    local has_kind_changes = next(decks) ~= nil or next(kind_multipliers) ~= nil or next(floor_stats_by_file) ~= nil
    if not has_kind_changes and hp_multiplier == nil and attack_multiplier == nil and exp_multiplier == nil then
        return
    end
    for _, file in ipairs(loaded_files.list_loaded_files(ENEMY_PARAMETER_POOL)) do
        local kind = get_kind_from_name(file.name)
        if kind ~= nil and file.data ~= 0 and read_magic(file.data) == ENP_MAGIC then
            apply_stats(file.data, file.name, kind)
            apply_deck(file.data, kind)
        end
    end
end

return {
    set_enemy_deck = set_enemy_deck,
    set_enemy_hp_multiplier = set_enemy_hp_multiplier,
    set_enemy_attack_multiplier = set_enemy_attack_multiplier,
    set_enemy_exp_multiplier = set_enemy_exp_multiplier,
    set_enemy_kind_multipliers = set_enemy_kind_multipliers,
    set_enemy_floor_stats = set_enemy_floor_stats,
    apply_enemy_stats = apply_enemy_stats
}
