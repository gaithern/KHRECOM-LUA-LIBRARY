local cffi = require("cffi")
local native = require("helpers.native")
local call_redirect = require("helpers.call_redirect")
local code_patch = require("helpers.code_patch")

local SETUP_FUNCTION_TYPE = "uint64_t (*)(uint64_t, uint64_t, uint64_t, uint64_t)"
local LOCK_STUB_KEY = "world_select_lock_stub"
local LOCK_STUB_SIZE = 128
local CONFIRM_STUB_OFFSET = 0
local DIM_STUB_OFFSET = 32
local LOCKED_FLAG_OFFSET = 96
local LOCKED_BRIGHTNESS_OFFSET = 100
local LOCKED_BRIGHTNESS = 0.4
local CMP_BYTE_RIP_LENGTH = 7
local JUMP_IF_EQUAL_LENGTH = 2
local MULSS_RIP_LENGTH = 8

local choice_handler = nil
local original_setup = nil
local locked_flag_address = 0

local function get_current_floor_number()
    local _, floor_index = native.call_function(getCurrentFloorIndexFunction)
    return (floor_index % 256) + 1
end

local function is_sora_story()
    local _, result = native.call_function(isSoraStoryFunction)
    return (result % 256) ~= 0
end

local function float_to_bytes(value)
    local packed = string.pack("<f", value)
    local bytes = {}
    for byte_number = 1, 4 do
        bytes[byte_number] = string.byte(packed, byte_number)
    end
    return bytes
end

local function append_compare_flag(code, code_address, flag_address)
    code_patch.append_bytes(code, {0x80, 0x3D})
    local next_instruction = code_address + CMP_BYTE_RIP_LENGTH
    code_patch.append_bytes(code, code_patch.to_bytes_32(flag_address - next_instruction))
    code_patch.append_bytes(code, {0x00})
end

local function build_confirm_stub(stub_address, flag_address, confirm_function_address)
    local code = {}
    append_compare_flag(code, stub_address, flag_address)
    code_patch.append_bytes(code, {0x75, 0x05})
    code_patch.append_relative_jump(code, stub_address, confirm_function_address)
    code_patch.append_bytes(code, {0x31, 0xC0, 0xC3})
    return code
end

local function build_dim_stub(stub_address, flag_address, brightness_address, brightness_function_address)
    local code = {}
    append_compare_flag(code, stub_address, flag_address)
    code_patch.append_bytes(code, {0x74, MULSS_RIP_LENGTH})
    code_patch.append_bytes(code, {0xF3, 0x0F, 0x59, 0x0D})
    local next_instruction = stub_address + CMP_BYTE_RIP_LENGTH + JUMP_IF_EQUAL_LENGTH + MULSS_RIP_LENGTH
    code_patch.append_bytes(code, code_patch.to_bytes_32(brightness_address - next_instruction))
    code_patch.append_relative_jump(code, stub_address, brightness_function_address)
    return code
end

local function install_lock_patches()
    local stub_address = code_patch.get_stub(LOCK_STUB_KEY, worldSelectConfirmCallSite, LOCK_STUB_SIZE)
    if stub_address == 0 then
        return false
    end
    local flag_address = stub_address + LOCKED_FLAG_OFFSET
    local brightness_address = stub_address + LOCKED_BRIGHTNESS_OFFSET
    local confirm_stub_address = stub_address + CONFIRM_STUB_OFFSET
    local dim_stub_address = stub_address + DIM_STUB_OFFSET
    WriteArray(brightness_address, float_to_bytes(LOCKED_BRIGHTNESS), true)
    local confirm_stub = build_confirm_stub(confirm_stub_address, flag_address, BASE_ADDR + worldSelectConfirmFunction)
    WriteArray(confirm_stub_address, confirm_stub, true)
    local dim_stub = build_dim_stub(dim_stub_address, flag_address, brightness_address, BASE_ADDR + worldSelectCardBrightnessFunction)
    WriteArray(dim_stub_address, dim_stub, true)
    local confirm_patched = code_patch.call_stub(worldSelectConfirmCallSite, worldSelectConfirmFunction, confirm_stub_address)
    if not confirm_patched then
        return false
    end
    locked_flag_address = flag_address
    local dim_patched = code_patch.call_stub(worldSelectCardBrightnessCallSite, worldSelectCardBrightnessFunction, dim_stub_address)
    if not dim_patched then
        native.log_debug("world select: could not install the locked card dimming patch")
    end
    return true
end

local function set_confirm_locked(locked)
    if locked_flag_address == 0 then
        if locked then
            native.log_debug("world select: could not lock confirm because the confirm patch is not installed")
        end
        return
    end
    if locked then
        WriteByte(locked_flag_address, 1, true)
    else
        WriteByte(locked_flag_address, 0, true)
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
    set_confirm_locked(false)
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
    set_confirm_locked(locked == true)
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
    if not install_lock_patches() then
        native.log_debug("world select: could not install the confirm lock patch")
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
