local log = require("helpers.log")
local memory_values = require("helpers.memory_values")

local CARD_CODE_SIZE = 0x1D
local SECOND_SLEIGHT_OFFSET = 0x0A
local MOV_ECX_OPCODE = 0xB9
local SLEIGHT_ID_OFFSET = 1
local SLEIGHT_COUNT = 2
local FIRST_SLEIGHT = 0x01
local LAST_SLEIGHT = 0x6D

local CARDS = {
    {card = 0x1A, vanilla = {0x0D, 0x14}},
    {card = 0x1B, vanilla = {0x0E, 0x15}},
    {card = 0x1C, vanilla = {0x0F, 0x16}},
    {card = 0x1D, vanilla = {0x10, 0x17}},
    {card = 0x1E, vanilla = {0x11, 0x18}},
    {card = 0x1F, vanilla = {0x12, 0x19}},
    {card = 0x20, vanilla = {0x13, 0x1A}},
    {card = 0x23, vanilla = {0x34, 0x35}},
    {card = 0x24, vanilla = {0x3D, 0x3E}},
    {card = 0x25, vanilla = {0x38, 0x39}},
    {card = 0x26, vanilla = {0x36, 0x37}},
    {card = 0x27, vanilla = {0x3F, 0x40}},
    {card = 0x28, vanilla = {0x3B, 0x3C}},
    {card = 0x29, vanilla = {0x41, 0x42}}
}

local changes = {}
local reported_wrong_code = false

local function find_card_number(card_id)
    for number, entry in ipairs(CARDS) do
        if entry.card == card_id then
            return number
        end
    end
    return nil
end

local function set_card_sleight(card_id, sleight_number, sleight_id)
    local card_number = find_card_number(card_id)
    if card_number == nil then
        log.log_debug("card sleights: that card does not give sleights")
        return false
    end
    if not memory_values.is_whole_number(sleight_number, 1, SLEIGHT_COUNT) then
        log.log_debug("card sleights: sleight number must be 1 or 2")
        return false
    end
    if not memory_values.is_whole_number(sleight_id, FIRST_SLEIGHT, LAST_SLEIGHT) then
        log.log_debug("card sleights: sleight id must be from 0x01 to 0x6D")
        return false
    end
    if changes[card_number] == nil then
        changes[card_number] = {}
    end
    changes[card_number][sleight_number] = sleight_id
    return true
end

local function get_code_address(card_number, sleight_number)
    local card_code = cardSleightCode + (card_number - 1) * CARD_CODE_SIZE
    return card_code + (sleight_number - 1) * SECOND_SLEIGHT_OFFSET
end

local function is_code_known()
    for card_number = 1, #CARDS do
        for sleight_number = 1, SLEIGHT_COUNT do
            if ReadByte(get_code_address(card_number, sleight_number)) ~= MOV_ECX_OPCODE then
                return false
            end
        end
    end
    return true
end

local function apply_card_sleights()
    if next(changes) == nil then
        return
    end
    if not is_code_known() then
        if not reported_wrong_code then
            reported_wrong_code = true
            log.log_debug("card sleights: the code is not where it should be")
        end
        return
    end
    for card_number, sleights in pairs(changes) do
        for sleight_number, sleight_id in pairs(sleights) do
            local address = get_code_address(card_number, sleight_number) + SLEIGHT_ID_OFFSET
            if ReadInt(address) ~= sleight_id then
                WriteInt(address, sleight_id)
            end
        end
    end
end

return {
    set_card_sleight = set_card_sleight,
    apply_card_sleights = apply_card_sleights
}
