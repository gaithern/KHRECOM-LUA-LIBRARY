local function byte_to_bits(byte)
    local bits = {}
    local remaining = byte
    for bit_number = 1, 8 do
        bits[bit_number] = remaining % 2
        remaining = math.floor(remaining / 2)
    end
    return bits
end

local function bits_to_byte(bits)
    local byte = 0
    local bit_value = 1
    for bit_number = 1, 8 do
        if bits[bit_number] == 1 then
            byte = byte + bit_value
        end
        bit_value = bit_value * 2
    end
    return byte
end

local function ReadBits(address, absolute)
    if absolute == nil then
        absolute = false
    end
    return byte_to_bits(ReadByte(address, absolute))
end

local function ReadBit(address, bit_number, absolute)
    if absolute == nil then
        absolute = false
    end
    local bits = ReadBits(address, absolute)
    return bits[bit_number]
end

local function WriteBit(address, bit_number, value, absolute)
    if absolute == nil then
        absolute = false
    end
    local bits = ReadBits(address, absolute)
    if value == 0 then
        bits[bit_number] = 0
    else
        bits[bit_number] = 1
    end
    WriteByte(address, bits_to_byte(bits), absolute)
end

local function contains(list, wanted_value)
    for _, value in ipairs(list) do
        if value == wanted_value then
            return true
        end
    end
    return false
end

return {
    byte_to_bits = byte_to_bits,
    bits_to_byte = bits_to_byte,
    ReadBits = ReadBits,
    ReadBit = ReadBit,
    WriteBit = WriteBit,
    contains = contains
}
