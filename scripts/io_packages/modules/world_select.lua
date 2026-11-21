local cffi = require("cffi")
local native = require("helpers.native")
local call_redirect = require("helpers.call_redirect")
local code_patch = require("helpers.code_patch")

local SETUP_FUNCTION_TYPE = "uint64_t (*)(uint64_t, uint64_t, uint64_t, uint64_t)"
local FULL_CIRCLE_DEGREES = 360
local EMPTY_CHOICE_STUB_KEY = "world_select_empty_choice_stub"
local EMPTY_CHOICE_STUB_SIZE = 64
local CONFIRM_STUB_OFFSET = 32

local choice_handler = nil
local original_setup = nil
local empty_choices_allowed = false

local function get_current_floor_number()
    local _, floor_index = native.call_function(getCurrentFloorIndexFunction)
    return (floor_index % 256) + 1
end

local function is_sora_story()
    local _, result = native.call_function(isSoraStoryFunction)
    return (result % 256) ~= 0
end

local function build_original_card_spacing_bytes()
    local code = {0xB8}
    code_patch.append_bytes(code, code_patch.to_bytes_32(FULL_CIRCLE_DEGREES))
    code_patch.append_bytes(code, {0x99, 0xF7, 0xF9, 0x89, 0x83})
    code_patch.append_bytes(code, code_patch.to_bytes_32(WORLD_SELECT_CARD_SPACING))
    return code
end

local function build_card_spacing_stub(stub_address, resume_address)
    local code = {0xB8}
    code_patch.append_bytes(code, code_patch.to_bytes_32(FULL_CIRCLE_DEGREES))
    code_patch.append_bytes(code, {0x85, 0xC9, 0x7E, 0x03, 0x99, 0xF7, 0xF9, 0x89, 0x83})
    code_patch.append_bytes(code, code_patch.to_bytes_32(WORLD_SELECT_CARD_SPACING))
    code_patch.append_relative_jump(code, stub_address, resume_address)
    return code
end

local function build_confirm_stub(stub_address, confirm_function_address)
    local code = {0x83, 0xB9}
    code_patch.append_bytes(code, code_patch.to_bytes_32(WORLD_SELECT_CHOICE_COUNT))
    code_patch.append_bytes(code, {0x00, 0x7E, 0x05})
    code_patch.append_relative_jump(code, stub_address, confirm_function_address)
    code_patch.append_bytes(code, {0x31, 0xC0, 0xC3})
    return code
end

local function install_empty_choice_patches()
    local stub_address = code_patch.get_stub(EMPTY_CHOICE_STUB_KEY, worldSelectCardSpacingDivide, EMPTY_CHOICE_STUB_SIZE)
    if stub_address == 0 then
        return false
    end
    local original_spacing_bytes = build_original_card_spacing_bytes()
    local resume_address = BASE_ADDR + worldSelectCardSpacingDivide + #original_spacing_bytes
    local spacing_stub = build_card_spacing_stub(stub_address, resume_address)
    WriteArray(stub_address, spacing_stub, true)
    local confirm_stub_address = stub_address + CONFIRM_STUB_OFFSET
    local confirm_stub = build_confirm_stub(confirm_stub_address, BASE_ADDR + worldSelectConfirmFunction)
    WriteArray(confirm_stub_address, confirm_stub, true)
    local spacing_patched = code_patch.jump_to_stub(worldSelectCardSpacingDivide, original_spacing_bytes, stub_address)
    local confirm_patched = code_patch.call_stub(worldSelectConfirmCallSite, worldSelectConfirmFunction, confirm_stub_address)
    return spacing_patched and confirm_patched
end

local function write_choices(world_select, world_ids)
    local choice_count = #world_ids
    if choice_count == 0 and not empty_choices_allowed then
        native.log_debug("world select: empty choice list refused because the empty choice patches are not installed")
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
    if choice_handler == nil then
        return
    end
    local floor_number = get_current_floor_number()
    local vanilla_choices = get_world_select_choices(world_select)
    local ok, world_ids = pcall(choice_handler, floor_number, is_sora_story(), vanilla_choices)
    if not ok then
        native.log_debug("world select handler failed: " .. tostring(world_ids))
        return
    end
    if world_ids == nil then
        return
    end
    write_choices(world_select, world_ids)
end

local function on_world_select_setup(world_select, second_argument, third_argument, fourth_argument)
    local result = original_setup(world_select, second_argument, third_argument, fourth_argument)
    local ok, error_message = pcall(apply_choice_handler, cffi.tonumber(world_select))
    if not ok then
        native.log_debug("world select hook failed: " .. tostring(error_message))
    end
    return result
end

local function install_hook()
    if original_setup == nil then
        original_setup = cffi.cast(SETUP_FUNCTION_TYPE, BASE_ADDR + worldSelectSetupFunction)
    end
    local first_installed = call_redirect.redirect_call(worldSelectSetupCallSite1, worldSelectSetupFunction, SETUP_FUNCTION_TYPE, on_world_select_setup)
    local second_installed = call_redirect.redirect_call(worldSelectSetupCallSite2, worldSelectSetupFunction, SETUP_FUNCTION_TYPE, on_world_select_setup)
    empty_choices_allowed = install_empty_choice_patches()
    if not empty_choices_allowed then
        native.log_debug("world select: could not install the empty choice patches")
    end
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
