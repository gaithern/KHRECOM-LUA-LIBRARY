local DATA_FILE_POOL = 1
local ARCHIVE_POOL = 23
local POOL_COUNT = 128
local POOL_POINTER_SIZE = 8
local POOL_FIRST_NODE_OFFSET = 0x10
local NODE_ENTRY_OFFSET = 0x08
local NODE_NEXT_OFFSET = 0x10
local ENTRY_FILE_OBJECT_OFFSET = 0x08
local ENTRY_NAME_OFFSET = 0x10
local FILE_OBJECT_DATA_OFFSET = 0x08
local MAX_NAME_LENGTH = 0x18
local MAX_NODES_PER_POOL = 5000

local known_names = {}
local update_lists = nil
local previous_lists = {}

local function read_name(address)
    local characters = {}
    for index = 0, MAX_NAME_LENGTH - 1 do
        local character = ReadByte(address + index, true)
        if character == 0 then
            break
        end
        characters[#characters + 1] = string.char(character)
    end
    return table.concat(characters)
end

local function read_file_data(entry)
    local file_object = ReadLong(entry + ENTRY_FILE_OBJECT_OFFSET, true)
    if file_object == 0 then
        return 0
    end
    return ReadLong(file_object + FILE_OBJECT_DATA_OFFSET, true)
end

local function get_name(entry, data)
    local name_start = ReadLong(entry + ENTRY_NAME_OFFSET, true)
    local known = known_names[entry]
    if known ~= nil and known.name_start == name_start and known.data == data then
        return known.name
    end
    known = {}
    known.name_start = name_start
    known.data = data
    known.name = read_name(entry + ENTRY_NAME_OFFSET)
    known_names[entry] = known
    return known.name
end

local function read_loaded_files(pool)
    local files = {}
    if pool < 0 or pool >= POOL_COUNT then
        return files
    end
    local pool_address = ReadLong(loadedFilePoolTable + pool * POOL_POINTER_SIZE)
    if pool_address == 0 then
        return files
    end
    local node = ReadLong(pool_address + POOL_FIRST_NODE_OFFSET, true)
    local node_count = 0
    while node ~= 0 and node_count < MAX_NODES_PER_POOL do
        local entry = ReadLong(node + NODE_ENTRY_OFFSET, true)
        if entry ~= 0 then
            local file = {}
            file.data = read_file_data(entry)
            file.name = get_name(entry, file.data)
            files[#files + 1] = file
        end
        node = ReadLong(node + NODE_NEXT_OFFSET, true)
        node_count = node_count + 1
    end
    return files
end

local function list_loaded_files(pool)
    if pool == nil then
        pool = DATA_FILE_POOL
    end
    if update_lists == nil then
        return read_loaded_files(pool)
    end
    if update_lists[pool] == nil then
        update_lists[pool] = read_loaded_files(pool)
    end
    return update_lists[pool]
end

local function start_update()
    update_lists = {}
end

local function finish_update()
    update_lists = nil
end

local function are_lists_equal(first, second)
    if first == nil or second == nil or #first ~= #second then
        return false
    end
    for index, file in ipairs(first) do
        if file.data ~= second[index].data or file.name ~= second[index].name then
            return false
        end
    end
    return true
end

local function did_files_change(pool)
    local files = list_loaded_files(pool)
    local changed = not are_lists_equal(files, previous_lists[pool])
    previous_lists[pool] = files
    return changed
end

local function get_loaded_file_map(pool)
    local file_map = {}
    for _, file in ipairs(list_loaded_files(pool)) do
        if file.data ~= 0 then
            file_map[string.lower(file.name)] = file.data
        end
    end
    return file_map
end

local function find_loaded_file(name, pool)
    local wanted_name = string.lower(name)
    for _, file in ipairs(list_loaded_files(pool)) do
        if string.lower(file.name) == wanted_name and file.data ~= 0 then
            return file.data
        end
    end
    return nil
end

local function find_loaded_drop_world()
    for _, file in ipairs(list_loaded_files(ARCHIVE_POOL)) do
        local world_text = string.match(string.upper(file.name), "^WO02(%d%d)%.BIN$")
        if world_text ~= nil then
            return tonumber(world_text)
        end
    end
    return nil
end

return {
    DATA_FILE_POOL = DATA_FILE_POOL,
    ARCHIVE_POOL = ARCHIVE_POOL,
    list_loaded_files = list_loaded_files,
    start_update = start_update,
    finish_update = finish_update,
    did_files_change = did_files_change,
    get_loaded_file_map = get_loaded_file_map,
    find_loaded_file = find_loaded_file,
    find_loaded_drop_world = find_loaded_drop_world
}
