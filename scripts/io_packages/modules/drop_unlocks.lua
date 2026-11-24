local log = require("helpers.log")

local COMPARE_OFFSET = 0x0B
local COMPARE_OPCODE = 0x83
local COMPARE_REGISTER = 0xFA
local LAST_CHECKED_CARD_OFFSET = 0x0D
local JUMP_OFFSET = 0x0E
local JUMP_OPCODE = 0x0F
local JUMP_IF_ABOVE = 0x87
local VANILLA_LAST_CHECKED_CARD = 0x30
local CHECK_NO_CARDS = 0x00

local wanted_last_checked_card = nil
local reported_wrong_code = false

local function is_unlock_check_code()
    local compare_address = dropUnlockCheckCode + COMPARE_OFFSET
    local jump_address = dropUnlockCheckCode + JUMP_OFFSET
    if ReadByte(compare_address) ~= COMPARE_OPCODE then
        return false
    end
    if ReadByte(compare_address + 1) ~= COMPARE_REGISTER then
        return false
    end
    if ReadByte(jump_address) ~= JUMP_OPCODE then
        return false
    end
    return ReadByte(jump_address + 1) == JUMP_IF_ABOVE
end

local function set_drops_ignore_unlocks(ignore_unlocks)
    if type(ignore_unlocks) ~= "boolean" then
        log.log_debug("drop unlocks: ignore_unlocks must be true or false")
        return false
    end
    if ignore_unlocks then
        wanted_last_checked_card = CHECK_NO_CARDS
    else
        wanted_last_checked_card = VANILLA_LAST_CHECKED_CARD
    end
    return true
end

local function get_drops_ignore_unlocks()
    if not is_unlock_check_code() then
        return nil
    end
    return ReadByte(dropUnlockCheckCode + LAST_CHECKED_CARD_OFFSET) == CHECK_NO_CARDS
end

local function apply_drop_unlocks()
    if wanted_last_checked_card == nil then
        return
    end
    if not is_unlock_check_code() then
        if not reported_wrong_code then
            reported_wrong_code = true
            log.log_debug("drop unlocks: the unlock check code is not where it should be")
        end
        return
    end
    local address = dropUnlockCheckCode + LAST_CHECKED_CARD_OFFSET
    if ReadByte(address) ~= wanted_last_checked_card then
        WriteByte(address, wanted_last_checked_card)
    end
end

return {
    set_drops_ignore_unlocks = set_drops_ignore_unlocks,
    get_drops_ignore_unlocks = get_drops_ignore_unlocks,
    apply_drop_unlocks = apply_drop_unlocks
}
