local log = require("helpers.log")
local memory_values = require("helpers.memory_values")

local PACK_FILE = "mogcardpack.bin"
local VALUE_FILE = "mogcardkaku.bin"
local FLOOR_FILE = "mogfloor.bin"

local PACK_COUNT = 16
local PRICES_OFFSET = 0x08
local FIRST_POOL_OFFSET = 0x28
local POOL_COUNT = 3
local TIER_COUNT = 4
local VALUE_COUNT = 10
local VALUE_WEIGHTS_OFFSET = 0x08
local FLOOR_GROUP_COUNT = 4
local FLOOR_ROWS_OFFSET = 0x08
local FLOOR_ROW_SIZE = 10
local MAX_PRICE = 32767
local MAX_WEIGHT = 100
local MAX_PACKS_PER_TIER = 20
local FIRST_CARD = 0x01
local LAST_CARD = 0x43
local LEA_OPCODE = 0x8D
local LEA_EAX_FROM_RBP = 0x45
local MOV_EAX_OPCODE = 0xB8
local MOV_ECX_OPCODE = 0xB9
local TEST_OPCODE = 0x85
local TEST_EAX_EAX = 0xC0
local JUMP_IF_NOT_ZERO = 0x75
local JUMP_ALWAYS = 0xEB

local CATEGORIES = {
    ATTACK = 1,
    MAGIC = 2,
    ITEM = 3,
    MIXED = 4
}

local FLOOR_GROUPS = {
    FLOOR_1 = 1,
    FLOORS_2_TO_6 = 2,
    FLOORS_7_TO_10 = 3,
    FLOORS_11_AND_UP = 4
}

local prices = {}
local value_weights = {}
local floor_offers = {}
local pools = {}
local fallback_cards = {}
local any_card_allowed = nil
local reported_problems = {}

local function report_once(message)
    if reported_problems[message] then
        return
    end
    reported_problems[message] = true
    log.log_debug("moogle shop: " .. message)
end

local function get_pack_number(category, tier)
    return (category - 1) * TIER_COUNT + tier
end

local function set_moogle_pack_price(category, tier, price)
    if not memory_values.is_whole_number(category, 1, 4) then
        log.log_debug("moogle shop: category must be from 1 to 4")
        return false
    end
    if not memory_values.is_whole_number(tier, 0, TIER_COUNT - 1) then
        log.log_debug("moogle shop: tier must be from 0 to 3")
        return false
    end
    if not memory_values.is_whole_number(price, 0, MAX_PRICE) then
        log.log_debug("moogle shop: price must be from 0 to 32767")
        return false
    end
    prices[get_pack_number(category, tier)] = price
    return true
end

local function set_moogle_value_weights(tier, weights)
    if not memory_values.is_whole_number(tier, 0, TIER_COUNT - 1) then
        log.log_debug("moogle shop: tier must be from 0 to 3")
        return false
    end
    if type(weights) ~= "table" or #weights ~= VALUE_COUNT then
        log.log_debug("moogle shop: value weights need 10 numbers, one for each value 0 to 9")
        return false
    end
    for index = 1, VALUE_COUNT do
        if not memory_values.is_whole_number(weights[index], 0, MAX_WEIGHT) then
            log.log_debug("moogle shop: value weight " .. index .. " must be from 0 to 100")
            return false
        end
    end
    value_weights[tier] = weights
    return true
end

local function set_moogle_floor_offer(floor_group, packs_per_tier)
    if not memory_values.is_whole_number(floor_group, 1, FLOOR_GROUP_COUNT) then
        log.log_debug("moogle shop: floor group must be from 1 to 4")
        return false
    end
    if type(packs_per_tier) ~= "table" or #packs_per_tier ~= TIER_COUNT then
        log.log_debug("moogle shop: packs per tier needs 4 numbers, one for each tier 0 to 3")
        return false
    end
    for index = 1, TIER_COUNT do
        if not memory_values.is_whole_number(packs_per_tier[index], 0, MAX_PACKS_PER_TIER) then
            log.log_debug("moogle shop: packs per tier must be from 0 to 20")
            return false
        end
    end
    floor_offers[floor_group] = packs_per_tier
    return true
end

local function set_moogle_pool(category, entries)
    if not memory_values.is_whole_number(category, 1, POOL_COUNT) then
        log.log_debug("moogle shop: pool category must be 1 (attack), 2 (magic) or 3 (item)")
        return false
    end
    if type(entries) ~= "table" then
        log.log_debug("moogle shop: pool entries must be a list")
        return false
    end
    for index, entry in ipairs(entries) do
        if type(entry) ~= "table" or not memory_values.is_whole_number(entry.card, FIRST_CARD, LAST_CARD) then
            log.log_debug("moogle shop: pool entry " .. index .. " needs a battle card id")
            return false
        end
        if type(entry.weights) ~= "table" or #entry.weights ~= TIER_COUNT then
            log.log_debug("moogle shop: pool entry " .. index .. " needs 4 weights, one for each tier")
            return false
        end
        for tier = 1, TIER_COUNT do
            if not memory_values.is_whole_number(entry.weights[tier], 0, MAX_WEIGHT) then
                log.log_debug("moogle shop: pool entry " .. index .. " weights must be from 0 to 100")
                return false
            end
        end
    end
    pools[category] = entries
    return true
end

local function set_moogle_fallback_card(category, card)
    if not memory_values.is_whole_number(category, 1, POOL_COUNT) then
        log.log_debug("moogle shop: fallback category must be 1 (attack), 2 (magic) or 3 (item)")
        return false
    end
    if not memory_values.is_whole_number(card, FIRST_CARD, LAST_CARD) then
        log.log_debug("moogle shop: fallback card must be a battle card id from 0x01 to 0x43")
        return false
    end
    fallback_cards[category] = card
    return true
end

local function set_moogle_any_card(allowed)
    if type(allowed) ~= "boolean" then
        log.log_debug("moogle shop: allowed must be true or false")
        return false
    end
    any_card_allowed = allowed
    return true
end

local function is_attack_fallback_code()
    local opcode = ReadByte(moogleFallbackAttackCard - 2)
    local operand = ReadByte(moogleFallbackAttackCard - 1)
    return opcode == LEA_OPCODE and operand == LEA_EAX_FROM_RBP
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

local function apply_fallback_cards()
    local attack_card = fallback_cards[CATEGORIES.ATTACK]
    if attack_card ~= nil then
        if is_attack_fallback_code() then
            keep_code_byte(moogleFallbackAttackCard, attack_card)
        else
            report_once("the attack fallback card code is not where it should be")
        end
    end
    local magic_card = fallback_cards[CATEGORIES.MAGIC]
    if magic_card ~= nil then
        if ReadByte(moogleFallbackMagicCard - 1) == MOV_ECX_OPCODE then
            keep_code_int(moogleFallbackMagicCard, magic_card)
        else
            report_once("the magic fallback card code is not where it should be")
        end
    end
    local item_card = fallback_cards[CATEGORIES.ITEM]
    if item_card ~= nil then
        if ReadByte(moogleFallbackItemCard - 1) == MOV_EAX_OPCODE then
            keep_code_int(moogleFallbackItemCard, item_card)
        else
            report_once("the item fallback card code is not where it should be")
        end
    end
end

local function is_journal_check_code()
    if ReadByte(moogleJournalCheck - 2) ~= TEST_OPCODE or ReadByte(moogleJournalCheck - 1) ~= TEST_EAX_EAX then
        return false
    end
    local jump = ReadByte(moogleJournalCheck)
    return jump == JUMP_IF_NOT_ZERO or jump == JUMP_ALWAYS
end

local function apply_any_card()
    if any_card_allowed == nil then
        return
    end
    if not is_journal_check_code() then
        report_once("the journal check code is not where it should be")
        return
    end
    if any_card_allowed then
        keep_code_byte(moogleJournalCheck, JUMP_ALWAYS)
    else
        keep_code_byte(moogleJournalCheck, JUMP_IF_NOT_ZERO)
    end
end

local function apply_prices(pack_file)
    for pack_number = 0, PACK_COUNT - 1 do
        local price = prices[pack_number]
        if price ~= nil then
            memory_values.keep_short(pack_file + PRICES_OFFSET + pack_number * 2, price)
        end
    end
end

local function apply_pool(pool_address, entries)
    local card_count = memory_values.read_signed_short(pool_address) + 1
    if #entries > card_count then
        report_once("a pool has " .. #entries .. " cards but the shop only has room for " .. card_count)
        return
    end
    local cards_address = pool_address + 2
    local weights_address = cards_address + card_count * 2
    for slot = 1, card_count do
        local entry = entries[slot]
        if entry ~= nil then
            memory_values.keep_short(cards_address + (slot - 1) * 2, entry.card)
        end
        for tier = 0, TIER_COUNT - 1 do
            local weight_address = weights_address + (tier * card_count + (slot - 1)) * 2
            if entry ~= nil then
                memory_values.keep_short(weight_address, entry.weights[tier + 1])
            else
                memory_values.keep_short(weight_address, 0)
            end
        end
    end
end

local function apply_pools(pack_file)
    local pool_address = pack_file + FIRST_POOL_OFFSET
    for category = 1, POOL_COUNT do
        local card_count = memory_values.read_signed_short(pool_address) + 1
        local entries = pools[category]
        if entries ~= nil then
            apply_pool(pool_address, entries)
        end
        pool_address = pool_address + 2 + card_count * 2 + TIER_COUNT * card_count * 2
    end
end

local function apply_value_weights(value_file)
    for tier = 0, TIER_COUNT - 1 do
        local weights = value_weights[tier]
        if weights ~= nil then
            local row_address = value_file + VALUE_WEIGHTS_OFFSET + tier * VALUE_COUNT * 2
            for index = 1, VALUE_COUNT do
                memory_values.keep_short(row_address + (index - 1) * 2, weights[index])
            end
        end
    end
end

local function apply_floor_offers(floor_file)
    for floor_group = 1, FLOOR_GROUP_COUNT do
        local packs_per_tier = floor_offers[floor_group]
        if packs_per_tier ~= nil then
            local row_address = floor_file + FLOOR_ROWS_OFFSET + (floor_group - 1) * FLOOR_ROW_SIZE
            for index = 1, TIER_COUNT do
                memory_values.keep_short(row_address + (index - 1) * 2, packs_per_tier[index])
            end
        end
    end
end

local function apply_moogle_shop(file_map)
    apply_fallback_cards()
    apply_any_card()
    local pack_file = file_map[PACK_FILE]
    if pack_file ~= nil then
        apply_prices(pack_file)
        apply_pools(pack_file)
    end
    local value_file = file_map[VALUE_FILE]
    if value_file ~= nil then
        apply_value_weights(value_file)
    end
    local floor_file = file_map[FLOOR_FILE]
    if floor_file ~= nil then
        apply_floor_offers(floor_file)
    end
end

return {
    CATEGORIES = CATEGORIES,
    FLOOR_GROUPS = FLOOR_GROUPS,
    set_moogle_pack_price = set_moogle_pack_price,
    set_moogle_value_weights = set_moogle_value_weights,
    set_moogle_floor_offer = set_moogle_floor_offer,
    set_moogle_pool = set_moogle_pool,
    set_moogle_fallback_card = set_moogle_fallback_card,
    set_moogle_any_card = set_moogle_any_card,
    apply_moogle_shop = apply_moogle_shop
}
