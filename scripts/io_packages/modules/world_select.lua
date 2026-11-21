local cffi = require("cffi")
local native = require("helpers.native")
local call_redirect = require("helpers.call_redirect")

local SETUP_FUNCTION_TYPE = "uint64_t (*)(uint64_t, uint64_t, uint64_t, uint64_t)"
local CONFIRM_FUNCTION_TYPE = "int (*)(uint64_t, int)"
local CARD_SCALE_FUNCTION_TYPE = "void (*)(uint64_t, float)"
local LOCKED_NAME_BLOCK_KEY = "world_select_locked_name"
local LOCKED_NAME_BLOCK_SIZE = 64
local LOCKED_NAME_MAX_LENGTH = 40
local LOCKED_SUFFIX = " (Locked)"
local CONFIRM_NOT_PRESSED = 0

local WORLD_SELECT_CARDS_OFFSET = 0x118
local WORLD_SELECT_LOGO_OFFSET = 0x170
local WORLD_SELECT_NAME_TEXT_OFFSET = 0x188
local TEXT_STRING_POINTER_OFFSET = 0x58
local POINTER_SIZE = 8

local LAYOUT_RED_OFFSET = 0x120
local LAYOUT_GREEN_OFFSET = 0x124
local LAYOUT_BLUE_OFFSET = 0x128
local LAYOUT_ALPHA_OFFSET = 0x12C
local LAYOUT_COLOR_ENABLED_OFFSET = 0x138

local LOCKED_CARD_BRIGHTNESS = 0.35
local LOCKED_LOGO_BRIGHTNESS = 0.15
local FULL_ALPHA = 1.0

local choice_handler = nil
local original_setup = nil
local original_confirm = nil
local original_card_scale = nil
local current_world_select = 0
local is_locked = false
local locked_name_address = 0

local function get_current_floor_number()
    local _, floor_index = native.call_function(getCurrentFloorIndexFunction)
    return (floor_index % 256) + 1
end

local function is_sora_story()
    local _, result = native.call_function(isSoraStoryFunction)
    return (result % 256) ~= 0
end

local function set_layout_brightness(layout, brightness)
    WriteFloat(layout + LAYOUT_RED_OFFSET, brightness, true)
    WriteFloat(layout + LAYOUT_GREEN_OFFSET, brightness, true)
    WriteFloat(layout + LAYOUT_BLUE_OFFSET, brightness, true)
    WriteFloat(layout + LAYOUT_ALPHA_OFFSET, FULL_ALPHA, true)
    WriteByte(layout + LAYOUT_COLOR_ENABLED_OFFSET, 1, true)
end

local function read_text(address)
    local text = ""
    for character_number = 0, LOCKED_NAME_MAX_LENGTH - 1 do
        local character = ReadByte(address + character_number, true)
        if character == 0 then
            break
        end
        text = text .. string.char(character)
    end
    return text
end

local function string_to_bytes(text)
    local bytes = {}
    for character_number = 1, #text do
        bytes[character_number] = string.byte(text, character_number)
    end
    bytes[#text + 1] = 0
    return bytes
end

local function dim_cards(world_select)
    local card_count = ReadInt(world_select + WORLD_SELECT_CHOICE_COUNT, true)
    for card_number = 0, card_count - 1 do
        local card = ReadLong(world_select + WORLD_SELECT_CARDS_OFFSET + card_number * POINTER_SIZE, true)
        if card ~= 0 then
            set_layout_brightness(card, LOCKED_CARD_BRIGHTNESS)
        end
    end
end

local function dim_logo(world_select)
    local logo = ReadLong(world_select + WORLD_SELECT_LOGO_OFFSET, true)
    if logo ~= 0 then
        set_layout_brightness(logo, LOCKED_LOGO_BRIGHTNESS)
    end
end

local function add_locked_to_name(world_select)
    if locked_name_address == 0 then
        return
    end
    local name_text = ReadLong(world_select + WORLD_SELECT_NAME_TEXT_OFFSET, true)
    if name_text == 0 then
        return
    end
    local name_address = ReadLong(name_text + TEXT_STRING_POINTER_OFFSET, true)
    if name_address == 0 or name_address == locked_name_address then
        return
    end
    local locked_name = read_text(name_address) .. LOCKED_SUFFIX
    WriteArray(locked_name_address, string_to_bytes(locked_name), true)
    WriteLong(name_text + TEXT_STRING_POINTER_OFFSET, locked_name_address, true)
end

local function show_locked_screen()
    if current_world_select == 0 then
        return
    end
    dim_cards(current_world_select)
    dim_logo(current_world_select)
    add_locked_to_name(current_world_select)
end

local function on_confirm_check(world_select, argument)
    if is_locked then
        return CONFIRM_NOT_PRESSED
    end
    return original_confirm(world_select, argument)
end

local function on_card_scale(layout, scale)
    original_card_scale(layout, scale)
    if not is_locked then
        return
    end
    local ok, error_message = pcall(show_locked_screen)
    if not ok then
        native.log_debug("world select: dimming the locked card failed: " .. tostring(error_message))
    end
end

local function write_choices(world_select, world_ids)
    local choice_count = #world_ids
    if choice_count == 0 then
        native.log_debug("world select: an empty choice list crashes the game, so the game's own list was kept")
        return
    end
    if choice_count > WORLD_SELECT_MAX_CHOICES then
        choice_count = WORLD_SELECT_MAX_CHOICES
    end
    for choice_number = 1, choice_count do
        WriteByte(world_select + WORLD_SELECT_CHOICES + choice_number - 1, world_ids[choice_number], true)
    end
    WriteInt(world_select + WORLD_SELECT_CHOICE_COUNT, choice_count, true)
end

local function get_world_select_choices(world_select)
    local choice_count = ReadInt(world_select + WORLD_SELECT_CHOICE_COUNT, true)
    local world_ids = {}
    for choice_number = 1, choice_count do
        world_ids[choice_number] = ReadByte(world_select + WORLD_SELECT_CHOICES + choice_number - 1, true)
    end
    return world_ids
end

local function apply_choice_handler(world_select)
    is_locked = false
    current_world_select = world_select
    if choice_handler == nil then
        return
    end
    local floor_number = get_current_floor_number()
    local vanilla_choices = get_world_select_choices(world_select)
    local ok, world_ids, locked = pcall(choice_handler, floor_number, is_sora_story(), vanilla_choices)
    if not ok then
        native.log_debug("world select handler failed: " .. tostring(world_ids))
        return
    end
    if world_ids == nil then
        return
    end
    write_choices(world_select, world_ids)
    is_locked = (locked == true)
end

local function on_world_select_setup(world_select, second_argument, third_argument, fourth_argument)
    local result = original_setup(world_select, second_argument, third_argument, fourth_argument)
    local ok, error_message = pcall(apply_choice_handler, cffi.tonumber(world_select))
    if not ok then
        native.log_debug("world select hook failed: " .. tostring(error_message))
    end
    return result
end

local function install_lock_hooks()
    if original_confirm == nil then
        original_confirm = cffi.cast(CONFIRM_FUNCTION_TYPE, BASE_ADDR + worldSelectConfirmFunction)
    end
    if original_card_scale == nil then
        original_card_scale = cffi.cast(CARD_SCALE_FUNCTION_TYPE, BASE_ADDR + worldSelectCardScaleFunction)
    end
    if locked_name_address == 0 then
        locked_name_address = native.persistent_block(LOCKED_NAME_BLOCK_KEY, LOCKED_NAME_BLOCK_SIZE)
    end
    local confirm_installed = call_redirect.redirect_call(worldSelectConfirmCallSite, worldSelectConfirmFunction, CONFIRM_FUNCTION_TYPE, on_confirm_check)
    if not confirm_installed then
        native.log_debug("world select: could not hook the confirm check, locked floors can be entered")
    end
    local card_scale_installed = call_redirect.redirect_call(worldSelectCardScaleCallSite, worldSelectCardScaleFunction, CARD_SCALE_FUNCTION_TYPE, on_card_scale)
    if not card_scale_installed then
        native.log_debug("world select: could not hook the card drawing, locked cards will not be dimmed")
    end
end

local function install_hook()
    if original_setup == nil then
        original_setup = cffi.cast(SETUP_FUNCTION_TYPE, BASE_ADDR + worldSelectSetupFunction)
    end
    local first_installed = call_redirect.redirect_call(worldSelectSetupCallSite1, worldSelectSetupFunction, SETUP_FUNCTION_TYPE, on_world_select_setup)
    local second_installed = call_redirect.redirect_call(worldSelectSetupCallSite2, worldSelectSetupFunction, SETUP_FUNCTION_TYPE, on_world_select_setup)
    install_lock_hooks()
    return first_installed and second_installed
end

local function set_world_select_handler(handler)
    choice_handler = handler
    if handler == nil then
        return true
    end
    return install_hook()
end

return {
    set_world_select_handler = set_world_select_handler,
    get_world_select_choices = get_world_select_choices
}
