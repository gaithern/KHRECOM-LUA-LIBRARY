local native = require("helpers.native")

local JUMP_OPCODE = 0xE9
local CALL_OPCODE = 0xE8
local NOP_OPCODE = 0x90
local RELATIVE_INSTRUCTION_LENGTH = 5
local SIGN_BIT_32 = 2147483648
local RANGE_32 = 4294967296

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

local function to_signed_32(value)
    if value >= SIGN_BIT_32 then
        return value - RANGE_32
    end
    return value
end

local function append_bytes(code, bytes)
    for _, byte_value in ipairs(bytes) do
        code[#code + 1] = byte_value
    end
end

local function append_relative_jump(code, code_address, destination)
    code[#code + 1] = JUMP_OPCODE
    local next_instruction = code_address + #code + 4
    append_bytes(code, to_bytes_32(destination - next_instruction))
end

local function bytes_match(rva, expected_bytes)
    local current_bytes = ReadArray(rva, #expected_bytes)
    for byte_number = 1, #expected_bytes do
        if current_bytes[byte_number] ~= expected_bytes[byte_number] then
            return false
        end
    end
    return true
end

local function relative_target(rva)
    local relative = to_signed_32(ReadInt(rva + 1))
    return BASE_ADDR + rva + RELATIVE_INSTRUCTION_LENGTH + relative
end

local function get_stub(key, near_rva, size)
    local slot = native.persistent_slot(key)
    if slot == 0 then
        return 0
    end
    if native.read_slot(slot) == 0 then
        local stub_address = native.allocate_near(BASE_ADDR + near_rva, size)
        if stub_address == 0 then
            return 0
        end
        native.write_slot(slot, stub_address)
    end
    return native.read_slot(slot)
end

local function write_relative(rva, opcode, destination, total_length)
    local patch = {opcode}
    append_bytes(patch, to_bytes_32(destination - (BASE_ADDR + rva + RELATIVE_INSTRUCTION_LENGTH)))
    while #patch < total_length do
        patch[#patch + 1] = NOP_OPCODE
    end
    WriteArray(rva, patch)
end

local function jump_to_stub(rva, original_bytes, stub_address)
    if ReadByte(rva) == JUMP_OPCODE and relative_target(rva) == stub_address then
        return true
    end
    if not bytes_match(rva, original_bytes) then
        return false
    end
    write_relative(rva, JUMP_OPCODE, stub_address, #original_bytes)
    return true
end

local function call_stub(rva, original_target_rva, stub_address)
    if ReadByte(rva) ~= CALL_OPCODE then
        return false
    end
    local current_target = relative_target(rva)
    if current_target == stub_address then
        return true
    end
    if current_target ~= BASE_ADDR + original_target_rva then
        return false
    end
    write_relative(rva, CALL_OPCODE, stub_address, RELATIVE_INSTRUCTION_LENGTH)
    return true
end

return {
    to_bytes_32 = to_bytes_32,
    append_bytes = append_bytes,
    append_relative_jump = append_relative_jump,
    get_stub = get_stub,
    jump_to_stub = jump_to_stub,
    call_stub = call_stub
}
