local cffi = require("cffi")
local native = require("helpers.native")
local call_redirect = require("helpers.call_redirect")

local BUILD_FUNCTION_TYPE = "uint64_t (*)(uint64_t)"
local FLOOR_COUNT = 13
local WARP_MENU_LAST_FLOOR_OFFSET = 0xD4
local WARP_MENU_HUNDRED_ACRE_ICON_OFFSET = 0xD8
local WARP_MENU_WORLD_TABLE_OFFSET = 0x228
local WARP_MENU_ICON_TABLE_OFFSET = 0x238
local NO_WORLD_ENTRY = 0xFF
local BLANK_ENTRY = 0x0E
local HUNDRED_ACRE_WOOD_WORLD_ID = 0x0A
local HUNDRED_ACRE_WOOD_ICON_BASE = 9
local FIRST_WORLD_WITHOUT_ICON = 0x0E

local original_build = nil
local display_handler = nil

local function get_icon_entry(warp_menu, world_id)
    if world_id < HUNDRED_ACRE_WOOD_WORLD_ID then
        return world_id - 1
    end
    if world_id == HUNDRED_ACRE_WOOD_WORLD_ID then
        return ReadByte(warp_menu + WARP_MENU_HUNDRED_ACRE_ICON_OFFSET, true) + HUNDRED_ACRE_WOOD_ICON_BASE
    end
    if world_id < FIRST_WORLD_WITHOUT_ICON then
        return world_id
    end
    return 0
end

local function get_world_to_show(floor_number)
    if display_handler == nil then
        return nil
    end
    local ok, world_id = pcall(display_handler, floor_number)
    if not ok then
        native.log_debug("floor warp handler failed: " .. tostring(world_id))
        return nil
    end
    return world_id
end

local function fill_unassigned_floors(warp_menu)
    for floor_index = 0, FLOOR_COUNT - 1 do
        local world_entry_address = warp_menu + WARP_MENU_WORLD_TABLE_OFFSET + floor_index
        local icon_entry_address = warp_menu + WARP_MENU_ICON_TABLE_OFFSET + floor_index
        if ReadByte(world_entry_address, true) == NO_WORLD_ENTRY then
            local floor_number = floor_index + 1
            local world_id = get_world_to_show(floor_number)
            if world_id == nil then
                WriteByte(world_entry_address, BLANK_ENTRY, true)
                WriteByte(icon_entry_address, BLANK_ENTRY, true)
            else
                WriteByte(world_entry_address, world_id - 1, true)
                WriteByte(icon_entry_address, get_icon_entry(warp_menu, world_id), true)
            end
        end
    end
    WriteInt(warp_menu + WARP_MENU_LAST_FLOOR_OFFSET, FLOOR_COUNT - 1, true)
end

local function on_warp_menu_build(warp_menu)
    local result = original_build(warp_menu)
    local ok, error_message = pcall(fill_unassigned_floors, cffi.tonumber(warp_menu))
    if not ok then
        native.log_debug("floor warp hook failed: " .. tostring(error_message))
    end
    return result
end

local function allow_warp_to_unassigned_floors(handler)
    display_handler = handler
    if original_build == nil then
        original_build = cffi.cast(BUILD_FUNCTION_TYPE, BASE_ADDR + floorWarpBuildFunction)
    end
    local installed = call_redirect.redirect_call(floorWarpBuildCallSite, floorWarpBuildFunction, BUILD_FUNCTION_TYPE, on_warp_menu_build)
    if not installed then
        native.log_debug("floor warp: could not hook the warp menu")
    end
    return installed
end

return {
    allow_warp_to_unassigned_floors = allow_warp_to_unassigned_floors
}
