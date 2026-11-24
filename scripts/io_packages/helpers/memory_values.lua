local SHORT_RANGE = 65536
local HALF_SHORT_RANGE = 32768

local function to_unsigned_short(value)
    return value % SHORT_RANGE
end

local function read_signed_short(address)
    local value = ReadShort(address, true)
    if value >= HALF_SHORT_RANGE then
        return value - SHORT_RANGE
    end
    return value
end

local function keep_short(address, value)
    local wanted = to_unsigned_short(value)
    if ReadShort(address, true) ~= wanted then
        WriteShort(address, wanted, true)
    end
end

local function keep_int(address, value)
    if ReadInt(address, true) ~= value then
        WriteInt(address, value, true)
    end
end

local function keep_long(address, value)
    if ReadLong(address, true) ~= value then
        WriteLong(address, value, true)
    end
end

local function keep_byte(address, value)
    if ReadByte(address, true) ~= value then
        WriteByte(address, value, true)
    end
end

local function is_whole_number(value, lowest, highest)
    if type(value) ~= "number" then
        return false
    end
    if value ~= math.floor(value) then
        return false
    end
    return value >= lowest and value <= highest
end

return {
    read_signed_short = read_signed_short,
    keep_short = keep_short,
    keep_int = keep_int,
    keep_long = keep_long,
    keep_byte = keep_byte,
    is_whole_number = is_whole_number
}
