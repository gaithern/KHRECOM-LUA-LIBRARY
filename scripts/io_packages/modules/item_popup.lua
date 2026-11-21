local cffi = require("cffi")
local native = require("helpers.native")
local call_redirect = require("helpers.call_redirect")
local card_ids = require("modules.card_ids")

local RECORD_BLOCK_KEY = "item_popup_record"
local RECORD_BLOCK_SIZE = 8
local RECORD_SIZE = 4
local ITEM_TABLE_ENTRY_SIZE = 16
local FIRST_ITEM_ID = 0x01
local LAST_ITEM_ID = 0xCA
local NO_ITEM_TYPE = 0
local SMALL_POPUP_KIND = 1
local PLAYER_POPUP_STATE_OFFSET = 0x390
local CUSTOM_TEXT_SECONDS_KEPT = 10
local FIRST_PLACEHOLDER_CARD = card_ids.GIMMICK_CARDS.GUARD_ARMOR
local PLACEHOLDER_CARD_COUNT = 8
local LOWEST_VALUE = 0
local HIGHEST_VALUE = 9
local PREMIUM_FLAG = 0x10
local NO_VALUE = 0xFF
local FIRST_SLEIGHT_INDEX = 0x00
local LAST_SLEIGHT_INDEX = 0x6D
local SLEIGHT_POPUP_OBJECT_SIZE = 0x2C0
local SLEIGHT_POPUP_PARENT_GROUP = 1

local NAME_FUNCTION_TYPE = "uint64_t (*)(uint64_t)"
local CUSTOM_TEXT_BLOCK_KEY = "item_popup_custom_text"
local CUSTOM_TEXT_SLOT_COUNT = 4
local CUSTOM_TEXT_SLOT_SIZE = 64
local CUSTOM_TEXT_MAX_LENGTH = CUSTOM_TEXT_SLOT_SIZE - 1

local record_address = 0
local custom_text_block = 0
local next_custom_text_slot = 0
local next_placeholder_number = 0
local pending_custom_texts = {}
local original_get_item_name = nil
local name_hooks_installed = false

local function get_item_type(item_id)
    return ReadByte(itemTable + item_id * ITEM_TABLE_ENTRY_SIZE)
end

local function build_record_bytes(item_id, value, is_premium)
    if type(item_id) ~= "number" then
        native.log_debug("item popup: item id is " .. tostring(item_id) .. ", check the card table name")
        return nil
    end
    if item_id < FIRST_ITEM_ID or item_id > LAST_ITEM_ID then
        native.log_debug("item popup: item id " .. tostring(item_id) .. " is outside the item table")
        return nil
    end
    local value_byte = NO_VALUE
    if value ~= nil then
        if type(value) ~= "number" then
            native.log_debug("item popup: value is " .. tostring(value) .. ", expected a number from 0 to 9 or nil")
            return nil
        end
        if value < LOWEST_VALUE or value > HIGHEST_VALUE then
            native.log_debug("item popup: value " .. tostring(value) .. " is not a card value from 0 to 9")
            return nil
        end
        value_byte = value
        if is_premium == true then
            value_byte = value + PREMIUM_FLAG
        end
    end
    local item_type = get_item_type(item_id)
    if item_type == NO_ITEM_TYPE then
        native.log_debug("item popup: item id " .. tostring(item_id) .. " has no item type")
        return nil
    end
    local item_id_low_byte = item_id % 256
    local item_id_high_byte = math.floor(item_id / 256)
    return {item_id_low_byte, item_id_high_byte, value_byte, item_type}
end

local function get_popup_kind()
    local player = ReadLong(attackPowerPointer)
    if player == 0 then
        return SMALL_POPUP_KIND
    end
    return ReadInt(player + PLAYER_POPUP_STATE_OFFSET, true) + 1
end

local function show_record(record_bytes)
    if record_address == 0 then
        record_address = native.persistent_block(RECORD_BLOCK_KEY, RECORD_BLOCK_SIZE)
        if record_address == 0 then
            native.log_debug("item popup: could not allocate the item record")
            return false
        end
    end
    WriteArray(record_address, record_bytes, true)
    native.call_function(showItemPopupFunction, record_address, get_popup_kind(), 0)
    return true
end

local function show_item_popup(item_id, value, is_premium)
    local record_bytes = build_record_bytes(item_id, value, is_premium)
    if record_bytes == nil then
        return false
    end
    return show_record(record_bytes)
end

local function records_match(record_bytes, other_record_bytes)
    for byte_number = 1, RECORD_SIZE do
        if record_bytes[byte_number] ~= other_record_bytes[byte_number] then
            return false
        end
    end
    return true
end

local function remove_old_custom_texts()
    local now = os.time()
    local kept = {}
    for _, pending in ipairs(pending_custom_texts) do
        if pending.expires_at > now then
            kept[#kept + 1] = pending
        end
    end
    pending_custom_texts = kept
end

local function find_pending_custom_text(record)
    remove_old_custom_texts()
    local record_bytes = ReadArray(record, RECORD_SIZE, true)
    local text_address = 0
    for _, pending in ipairs(pending_custom_texts) do
        if records_match(pending.record_bytes, record_bytes) then
            text_address = pending.text_address
        end
    end
    return text_address
end

local function get_next_placeholder_card()
    local placeholder_card = FIRST_PLACEHOLDER_CARD + next_placeholder_number
    next_placeholder_number = (next_placeholder_number + 1) % PLACEHOLDER_CARD_COUNT
    return placeholder_card
end

local function on_get_item_name(record)
    local ok, text_address = pcall(find_pending_custom_text, cffi.tonumber(record))
    if not ok then
        native.log_debug("item popup: custom text lookup failed: " .. tostring(text_address))
        text_address = 0
    end
    if text_address ~= 0 then
        return text_address
    end
    return original_get_item_name(record)
end

local function install_name_hooks()
    if name_hooks_installed then
        return true
    end
    if original_get_item_name == nil then
        original_get_item_name = cffi.cast(NAME_FUNCTION_TYPE, BASE_ADDR + getItemNameFunction)
    end
    local first_installed = call_redirect.redirect_call(popupItemNameCallSite1, getItemNameFunction, NAME_FUNCTION_TYPE, on_get_item_name)
    local second_installed = call_redirect.redirect_call(popupItemNameCallSite2, getItemNameFunction, NAME_FUNCTION_TYPE, on_get_item_name)
    local queued_installed = call_redirect.redirect_call(popupQueuedItemNameCallSite, getItemNameFunction, NAME_FUNCTION_TYPE, on_get_item_name)
    name_hooks_installed = first_installed and second_installed and queued_installed
    if not name_hooks_installed then
        native.log_debug("item popup: could not hook every popup name lookup, custom text may not show")
    end
    return name_hooks_installed
end

local function write_custom_text(text)
    if custom_text_block == 0 then
        custom_text_block = native.persistent_block(CUSTOM_TEXT_BLOCK_KEY, CUSTOM_TEXT_SLOT_COUNT * CUSTOM_TEXT_SLOT_SIZE)
        if custom_text_block == 0 then
            return 0
        end
    end
    local text_address = custom_text_block + next_custom_text_slot * CUSTOM_TEXT_SLOT_SIZE
    next_custom_text_slot = (next_custom_text_slot + 1) % CUSTOM_TEXT_SLOT_COUNT
    local text_bytes = {}
    for character_number = 1, #text do
        text_bytes[character_number] = string.byte(text, character_number)
    end
    text_bytes[#text + 1] = 0
    WriteArray(text_address, text_bytes, true)
    return text_address
end

local function show_custom_popup(text, item_id, value, is_premium)
    if item_id == nil then
        item_id = get_next_placeholder_card()
    end
    if type(text) ~= "string" then
        native.log_debug("custom popup: text is " .. tostring(text) .. ", expected a string")
        return false
    end
    if #text > CUSTOM_TEXT_MAX_LENGTH then
        native.log_debug("custom popup: text is longer than " .. tostring(CUSTOM_TEXT_MAX_LENGTH) .. " characters")
        return false
    end
    local record_bytes = build_record_bytes(item_id, value, is_premium)
    if record_bytes == nil then
        return false
    end
    install_name_hooks()
    local text_address = write_custom_text(text)
    if text_address == 0 then
        native.log_debug("custom popup: could not allocate the text buffer")
        return false
    end
    if #pending_custom_texts >= CUSTOM_TEXT_SLOT_COUNT then
        table.remove(pending_custom_texts, 1)
    end
    local expires_at = os.time() + CUSTOM_TEXT_SECONDS_KEPT
    pending_custom_texts[#pending_custom_texts + 1] = {record_bytes = record_bytes, text_address = text_address, expires_at = expires_at}
    return show_record(record_bytes)
end

local function show_sleight_popup(sleight_index)
    if type(sleight_index) ~= "number" then
        native.log_debug("sleight popup: sleight index is " .. tostring(sleight_index) .. ", expected a number")
        return false
    end
    if sleight_index < FIRST_SLEIGHT_INDEX or sleight_index > LAST_SLEIGHT_INDEX then
        native.log_debug("sleight popup: sleight index " .. tostring(sleight_index) .. " is outside the sleight list")
        return false
    end
    local _, popup_object = native.call_function(gameAllocateFunction, SLEIGHT_POPUP_OBJECT_SIZE)
    if popup_object == 0 then
        native.log_debug("sleight popup: the game could not allocate the popup")
        return false
    end
    local _, parent_task = native.call_function(getTaskParentFunction, SLEIGHT_POPUP_PARENT_GROUP)
    native.call_function(sleightPopupConstructor, popup_object, parent_task, sleight_index)
    return true
end

return {
    show_item_popup = show_item_popup,
    show_custom_popup = show_custom_popup,
    show_sleight_popup = show_sleight_popup
}
