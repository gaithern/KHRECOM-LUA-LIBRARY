local cffi = require("cffi")
local native = require("helpers.native")

local CALL_OPCODE = 0xE8
local JUMP_OPCODE = 0xE9
local CALL_LENGTH = 5
local JUMP_STUB_LENGTH = 14
local JUMP_STUB_DESTINATION = 6
local JUMP_TO_ADDRESS_BELOW = {0xFF, 0x25, 0x00, 0x00, 0x00, 0x00}
local SIGN_BIT_32 = 2147483648
local RANGE_32 = 4294967296

local redirects = {}

local function to_signed_32(value)
    if value >= SIGN_BIT_32 then
        return value - RANGE_32
    end
    return value
end

local function to_bytes_32(value)
    if value < 0 then
        value = value + RANGE_32
    end
    local bytes = {}
    local remaining = value
    for byte_number = 1, 4 do
        bytes[byte_number] = remaining % 256
        remaining = math.floor(remaining / 256)
    end
    return bytes
end

local function call_target(call_site)
    local relative = to_signed_32(ReadInt(call_site + 1))
    return BASE_ADDR + call_site + CALL_LENGTH + relative
end

local function point_call_at(call_site, destination)
    local relative = destination - (BASE_ADDR + call_site + CALL_LENGTH)
    WriteArray(call_site + 1, to_bytes_32(relative))
end

local function get_stub_for(call_site)
    local slot = native.persistent_slot(string.format("call_redirect_stub_%X", call_site))
    if slot == 0 then
        return 0
    end
    if native.read_slot(slot) == 0 then
        local stub_address = native.allocate_near(BASE_ADDR + call_site, JUMP_STUB_LENGTH)
        if stub_address == 0 then
            return 0
        end
        WriteArray(stub_address, JUMP_TO_ADDRESS_BELOW, true)
        native.write_slot(slot, stub_address)
    end
    return native.read_slot(slot)
end

local function restore(call_site)
    local redirect = redirects[call_site]
    if redirect == nil then
        return
    end
    redirects[call_site] = nil
    local stub_destination = ReadLong(redirect.stub_address + JUMP_STUB_DESTINATION, true)
    if stub_destination ~= native.to_address(redirect.callback) then
        return
    end
    point_call_at(call_site, BASE_ADDR + redirect.original_target)
end

local function redirect_call(call_site, expected_target, function_type, lua_function)
    if redirects[call_site] ~= nil then
        return true
    end
    local opcode = ReadByte(call_site)
    if opcode ~= CALL_OPCODE and opcode ~= JUMP_OPCODE then
        return false
    end
    local stub_address = get_stub_for(call_site)
    if stub_address == 0 then
        return false
    end
    local current_target = call_target(call_site)
    if current_target ~= BASE_ADDR + expected_target and current_target ~= stub_address then
        return false
    end
    local callback = cffi.cast(function_type, lua_function)
    WriteLong(stub_address + JUMP_STUB_DESTINATION, native.to_address(callback), true)
    point_call_at(call_site, stub_address)
    local restore_when_lua_closes = setmetatable({}, {__gc = function() restore(call_site) end})
    redirects[call_site] = {
        original_target = expected_target,
        stub_address = stub_address,
        callback = callback,
        restore_when_lua_closes = restore_when_lua_closes
    }
    return true
end

return {
    call_target = call_target,
    redirect_call = redirect_call,
    restore = restore
}
