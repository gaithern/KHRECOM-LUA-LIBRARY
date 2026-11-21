local cffi = require("cffi")

cffi.cdef[[
    void* VirtualAlloc(void* address, size_t size, uint32_t allocation_type, uint32_t protect);
    int VirtualFree(void* address, size_t size, uint32_t free_type);
    void* CreateFileMappingA(void* file, void* attributes, uint32_t protect, uint32_t size_high, uint32_t size_low, const char* name);
    void* MapViewOfFile(void* mapping, uint32_t access, uint32_t offset_high, uint32_t offset_low, size_t size);
    uint32_t GetCurrentProcessId(void);
]]

local MEM_COMMIT_AND_RESERVE = 0x3000
local MEM_RELEASE = 0x8000
local PAGE_READWRITE = 0x04
local PAGE_EXECUTE_READWRITE = 0x40
local FILE_MAP_ALL_ACCESS = 0xF001F
local ALLOCATION_GRANULARITY = 0x10000
local NEAR_SEARCH_RANGE = 0x70000000
local PERSISTENT_SLOT_PREFIX = "Local\\khrecom_lua_library_"
local LOG_FILE_NAME = "khrecom_lua_library.log"

local scratch_floats = nil
local log_path = nil
local slot_views = {}

local function to_address(pointer)
    return cffi.tonumber(cffi.cast("uintptr_t", pointer))
end

local function get_function_type(argument_count)
    if argument_count == 0 then
        return "uint64_t (*)(void)"
    end
    local argument_types = {}
    for argument_number = 1, argument_count do
        argument_types[argument_number] = "uint64_t"
    end
    return "uint64_t (*)(" .. table.concat(argument_types, ", ") .. ")"
end

local function call_function(rva, ...)
    local arguments = {...}
    local game_function = cffi.cast(get_function_type(#arguments), BASE_ADDR + rva)
    local result = game_function(table.unpack(arguments))
    return true, cffi.tonumber(result)
end

local function write_floats(...)
    if scratch_floats == nil then
        scratch_floats = cffi.new("float[16]")
    end
    local values = {...}
    for value_number = 1, #values do
        scratch_floats[value_number - 1] = values[value_number]
    end
    return to_address(scratch_floats)
end

local function allocate(size, executable)
    local protect = PAGE_READWRITE
    if executable then
        protect = PAGE_EXECUTE_READWRITE
    end
    return to_address(cffi.C.VirtualAlloc(nil, size, MEM_COMMIT_AND_RESERVE, protect))
end

local function try_allocate_at(address, size)
    local aligned_address = address - (address % ALLOCATION_GRANULARITY)
    local block = cffi.C.VirtualAlloc(cffi.cast("void*", aligned_address), size, MEM_COMMIT_AND_RESERVE, PAGE_EXECUTE_READWRITE)
    return to_address(block)
end

local function allocate_near(target, size)
    local offset = 0
    while offset < NEAR_SEARCH_RANGE do
        local above = try_allocate_at(target + offset, size)
        if above ~= 0 then
            return above
        end
        local below = try_allocate_at(target - offset, size)
        if below ~= 0 then
            return below
        end
        offset = offset + ALLOCATION_GRANULARITY
    end
    return 0
end

local function free(address)
    return cffi.C.VirtualFree(cffi.cast("void*", address), 0, MEM_RELEASE) ~= 0
end

local function copy_memory(destination, source, size)
    cffi.copy(cffi.cast("void*", destination), cffi.cast("void*", source), size)
    return true
end

local function persistent_slot(key)
    if slot_views[key] ~= nil then
        return slot_views[key]
    end
    local name = PERSISTENT_SLOT_PREFIX .. cffi.C.GetCurrentProcessId() .. "_" .. key
    local invalid_handle = cffi.cast("void*", -1)
    local mapping = cffi.C.CreateFileMappingA(invalid_handle, nil, PAGE_READWRITE, 0, 8, name)
    if to_address(mapping) == 0 then
        return 0
    end
    local view = to_address(cffi.C.MapViewOfFile(mapping, FILE_MAP_ALL_ACCESS, 0, 0, 8))
    if view == 0 then
        return 0
    end
    slot_views[key] = view
    return view
end

local function read_slot(slot)
    local pointer = cffi.cast("uint64_t*", slot)
    return cffi.tonumber(pointer[0])
end

local function write_slot(slot, value)
    local pointer = cffi.cast("uint64_t*", slot)
    pointer[0] = value
end

local function persistent_block(key, size)
    local slot = persistent_slot(key)
    if slot == 0 then
        return 0
    end
    if read_slot(slot) == 0 then
        write_slot(slot, allocate(size, false))
    end
    return read_slot(slot)
end

local function find_log_path()
    if type(SCRIPT_PATH) ~= "string" then
        return LOG_FILE_NAME
    end
    return SCRIPT_PATH .. "/io_packages/" .. LOG_FILE_NAME
end

local function log_debug(message)
    if log_path == nil then
        log_path = find_log_path()
    end
    local file = io.open(log_path, "a")
    if file == nil then
        return
    end
    file:write("[" .. os.date("%H:%M:%S") .. "] " .. message .. "\n")
    file:close()
end

return {
    to_address = to_address,
    call_function = call_function,
    write_floats = write_floats,
    allocate = allocate,
    allocate_near = allocate_near,
    free = free,
    copy_memory = copy_memory,
    persistent_slot = persistent_slot,
    read_slot = read_slot,
    write_slot = write_slot,
    persistent_block = persistent_block,
    log_debug = log_debug
}
