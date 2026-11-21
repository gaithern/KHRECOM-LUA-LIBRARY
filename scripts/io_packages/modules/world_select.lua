local cffi = require("cffi")
local native = require("helpers.native")
local call_redirect = require("helpers.call_redirect")

local SETUP_FUNCTION_TYPE = "uint64_t (*)(uint64_t, uint64_t, uint64_t, uint64_t)"

local choice_handler = nil
local original_setup = nil

local function get_current_floor_number()
    local _, floor_index = native.call_function(getCurrentFloorIndexFunction)
    return (floor_index % 256) + 1
end

local function is_sora_story()
    local _, result = native.call_function(isSoraStoryFunction)
    return (result % 256) ~= 0
end

local function write_choices(world_select, world_ids)
    local choice_count = #world_ids
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
