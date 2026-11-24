local log = require("helpers.log")
local memory_values = require("helpers.memory_values")

local CARD_INIT_FILE = "cardinit.bin"
local INDEX_POINTER_OFFSET = 0x08
local DATA_POINTER_OFFSET = 0x0C
local WORD_SIZE = 2
local HEADER_WORD_COUNT = 8
local VALUE_SCALE = 256
local STARTING_CARD_COUNT = 13
local FIRST_CARD = 0x01
local LAST_CARD = 0x7C
local LAST_VALUE = 9

local starting_cards = nil
local reported_wrong_size = false

local function set_starting_deck(cards)
    if type(cards) ~= "table" or #cards ~= STARTING_CARD_COUNT then
        log.log_debug("starting deck: the deck must be a list of 13 {card, value}")
        return false
    end
    for index, entry in ipairs(cards) do
        if type(entry) ~= "table" then
            log.log_debug("starting deck: entry " .. index .. " must be a table")
            return false
        end
        if not memory_values.is_whole_number(entry.card, FIRST_CARD, LAST_CARD) then
            log.log_debug("starting deck: entry " .. index .. " has a bad card id")
            return false
        end
        if not memory_values.is_whole_number(entry.value, 0, LAST_VALUE) then
            log.log_debug("starting deck: entry " .. index .. " needs a value from 0 to 9")
            return false
        end
    end
    starting_cards = cards
    return true
end

local function apply_starting_deck(file_map)
    if starting_cards == nil then
        return
    end
    local file_data = file_map[CARD_INIT_FILE]
    if file_data == nil then
        return
    end
    local index_address = file_data + ReadInt(file_data + INDEX_POINTER_OFFSET, true)
    local data_address = file_data + ReadInt(file_data + DATA_POINTER_OFFSET, true)
    local first_word = ReadShort(index_address, true)
    local end_word = ReadShort(index_address + WORD_SIZE, true)
    if end_word - first_word ~= HEADER_WORD_COUNT + STARTING_CARD_COUNT then
        if not reported_wrong_size then
            reported_wrong_size = true
            log.log_debug("starting deck: the new game deck is not the size it should be")
        end
        return
    end
    local cards_address = data_address + (first_word + HEADER_WORD_COUNT) * WORD_SIZE
    for index, entry in ipairs(starting_cards) do
        local wanted = entry.card + entry.value * VALUE_SCALE
        memory_values.keep_short(cards_address + (index - 1) * WORD_SIZE, wanted)
    end
end

return {
    set_starting_deck = set_starting_deck,
    apply_starting_deck = apply_starting_deck
}
