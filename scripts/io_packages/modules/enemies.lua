local log = require("helpers.log")
local memory_values = require("helpers.memory_values")
local loaded_files = require("modules.loaded_files")

local ARENA_FILE_POOL = 18
local FIRST_ROOM_CATEGORY = 100
local FIRST_WORLD = 1
local CASTLE_HALLS = 0
local LAST_WORLD = 13
local FIRST_ARENA_ROOM = 1000
local LAST_ARENA_ROOM = 1999
local POINTER_SIZE = 8
local MANIFEST_ENTRY_SIZE = 16
local MANIFEST_TYPE_OFFSET = 2
local MANIFEST_NAME_OFFSET = 8
local MANIFEST_END = 0xFFFF
local MANIFEST_RESOURCE_TYPE = 0x27
local MAX_MANIFEST_ENTRIES = 5000
local ENEMY_RESOURCE_BASE = 120000
local FIRST_ENEMY_KIND = 1
local LAST_ENEMY_KIND = 9999
local MAX_NAME_LENGTH = 8

local FIRST_OSD_OFFSETS = {0x40, 0x60}
local ARCHIVE_ENTRY_SIZE = 0x20
local ARCHIVE_NAME_OFFSET = 4
local MAX_ARCHIVE_ENTRIES = 2
local MAX_ARENA_FILE_SIZE = 0x10000
local OSD_VERSION_OFFSET = 4
local OSD_FORMATIONS_OFFSET = 8
local FORMATION_COUNT = 32
local SETS_PER_GROUP = 16
local BATTLE_GROUP = 1
local SET_COUNT_OFFSET = 4
local SET_RECORDS_OFFSET = 8
local RECORD_SIZE = 0x30
local RECORD_KIND_OFFSET = 0x16
local RECORD_VARIANT_OFFSET = 0x20
local BOSS_FORMATION = 0
local ONE_BOSS = 1
local NO_MORE_WAVES = 0
local SET_MORE_WAVES_OFFSET = 12
local POSITION_SIZE = 4
local SMALLEST_MOVE = 0.001
local FARTHEST_POSITION = 100
local FIRST_BOSS_KIND = 100
local LAST_BOSS_KIND = 199
local LAST_BOSS_VARIANT = 9
local GROUP_COUNT = 4
local OSD_MAGIC = "@OSD"
local SWAP_MARK_OFFSET = 0x3B
local SWAP_MARK = 0x5A
local FIRST_SWAP_ARENA = 1001
local LAST_SWAP_ARENA = 1007
local LAST_FIELD_ROOM = 999
local TUTORIAL_WORLD = 1
local TUTORIAL_ARENA = 1030
local ROOM_PRIZE_CHECKS = {
    {room = "Black Room", kinds = {17, 35}, offset = 0x83, vanilla = {0x75, 0x54}, changed = {0x90, 0x90}},
    {room = "White Room", kinds = {16, 34}, offset = 0x55F7, vanilla = {0x74, 0x29}, changed = {0xEB, 0x29}}
}
local LAST_HEARTLESS_KIND = 36
local HANDLE_FLAG = 0x80000000
local HANDLE_SEGMENT_SIZE = 0x2000000
local HANDLE_SEGMENT_COUNT = 64
local UNSIGNED_INT_RANGE = 0x100000000

local SWAP_ROOM_KINDS = {
    [1] = {[1001] = {1, 2, 3, 4}, [1002] = {16}, [1003] = {17}, [1004] = {1}, [1005] = {1, 2, 3, 4}, [1030] = {1}},
    [2] = {[1001] = {1, 10, 11, 5, 6, 28}, [1002] = {1, 5, 10, 11, 15, 28}, [1003] = {5, 6, 11, 15, 28, 1}, [1004] = {16, 28}, [1005] = {17, 28}, [1006] = {1}},
    [3] = {[1001] = {1, 4, 7, 9, 8, 28}, [1002] = {16, 28}, [1003] = {17, 28}, [1004] = {1, 4, 7, 8, 9, 28}, [1005] = {1}},
    [4] = {[3] = {1}, [1001] = {1, 2, 3, 9, 30, 31}, [1002] = {1, 2, 3, 9, 30, 31}, [1003] = {16}, [1004] = {17}, [1005] = {1}},
    [5] = {[1001] = {1, 9, 14, 15, 28, 5}, [1002] = {1, 5, 6, 9, 28, 29}, [1003] = {1, 6, 15, 28, 29, 5}, [1004] = {1, 5, 6, 14, 15, 28}, [1005] = {16, 28}, [1006] = {17, 28}, [1007] = {1}},
    [6] = {[26] = {32}, [1001] = {32, 12, 13, 33, 36}, [1002] = {32, 12, 13, 33, 36}, [1003] = {34}, [1004] = {35}, [1005] = {32}},
    [7] = {[26] = {1}, [1001] = {14, 18, 19, 20, 23}, [1002] = {16}, [1003] = {17}, [1004] = {1}},
    [8] = {[1001] = {1, 5, 21, 22, 23, 28}, [1002] = {1, 5, 22, 23, 28, 30}, [1003] = {1, 5, 21, 22, 28, 30}, [1004] = {16, 28}, [1005] = {17, 28}, [1006] = {1}},
    [9] = {[1001] = {1, 23, 24, 25, 26}, [1002] = {1, 23, 24, 26, 25}, [1003] = {16, 28}, [1004] = {17, 28}, [1005] = {1}, [1006] = {1, 23, 24, 26, 29}, [1007] = {1, 23, 24, 26, 29}},
    [11] = {[1001] = {1, 2, 15, 28}, [1002] = {16, 28}, [1003] = {17, 28}, [1004] = {1}},
    [12] = {[1001] = {1, 23, 28, 29, 30, 31}, [1002] = {1, 28, 29, 31, 23}, [1003] = {1, 28, 29, 31, 2, 30}, [1004] = {16, 28}, [1005] = {17, 28}, [1006] = {1}},
    [13] = {[1001] = {3, 4, 6, 25, 27, 23}, [1002] = {1, 3, 5, 23, 26, 27}, [1003] = {3, 4, 24, 25, 26, 27}, [1004] = {1, 3, 6, 24, 25, 27}, [1005] = {16}, [1006] = {17}, [1007] = {1}}
}

local world_swaps = {}
local boss_fights = {}
local world_enemy_kinds = {}
local formation_changes = {}
local kind_names = {}
local kind_names_collected = false
local arena_entries = {}
local reported_problems = {}

local function report_once(message)
    if reported_problems[message] then
        return
    end
    reported_problems[message] = true
    log.log_debug("enemies: " .. message)
end

local function read_unsigned_int(address)
    local value = ReadInt(address, true)
    if value < 0 then
        value = value + UNSIGNED_INT_RANGE
    end
    return value
end

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

local function get_room_manifest(world_id)
    return ReadLong(resourceManifestTable + (FIRST_ROOM_CATEGORY + world_id) * POINTER_SIZE)
end

local function get_enemy_kind_from_name(name)
    local number = tonumber(name)
    if number == nil then
        return nil
    end
    local kind = number - ENEMY_RESOURCE_BASE
    if kind < FIRST_ENEMY_KIND or kind > LAST_ENEMY_KIND then
        return nil
    end
    return kind
end

local function find_enemy_entries(world_id, arena_room_code)
    local entries = {}
    local manifest = get_room_manifest(world_id)
    if manifest == 0 then
        return entries
    end
    for index = 0, MAX_MANIFEST_ENTRIES - 1 do
        local entry = manifest + index * MANIFEST_ENTRY_SIZE
        local item = ReadShort(entry, true)
        if item == MANIFEST_END then
            break
        end
        if item == arena_room_code and ReadShort(entry + MANIFEST_TYPE_OFFSET, true) == MANIFEST_RESOURCE_TYPE then
            local name = read_name(ReadLong(entry + MANIFEST_NAME_OFFSET, true))
            if get_enemy_kind_from_name(name) ~= nil then
                entries[#entries + 1] = entry
            end
        end
    end
    return entries
end

local function collect_kind_names()
    if kind_names_collected then
        return
    end
    kind_names_collected = true
    for world_id = CASTLE_HALLS, LAST_WORLD do
        local manifest = get_room_manifest(world_id)
        if manifest ~= 0 then
            for index = 0, MAX_MANIFEST_ENTRIES - 1 do
                local entry = manifest + index * MANIFEST_ENTRY_SIZE
                if ReadShort(entry, true) == MANIFEST_END then
                    break
                end
                if ReadShort(entry + MANIFEST_TYPE_OFFSET, true) == MANIFEST_RESOURCE_TYPE then
                    local name_address = ReadLong(entry + MANIFEST_NAME_OFFSET, true)
                    local kind = get_enemy_kind_from_name(read_name(name_address))
                    if kind ~= nil and kind_names[kind] == nil then
                        kind_names[kind] = name_address
                    end
                end
            end
        end
    end
end

local function get_arena_entries(world_id, arena_room_code)
    local key = world_id .. "/" .. arena_room_code
    if arena_entries[key] == nil then
        arena_entries[key] = find_enemy_entries(world_id, arena_room_code)
    end
    return arena_entries[key]
end

local function check_world_and_arena(world_id, arena_room_code)
    if not memory_values.is_whole_number(world_id, FIRST_WORLD, LAST_WORLD) then
        log.log_debug("enemies: world id must be from 1 to 13")
        return false
    end
    if not memory_values.is_whole_number(arena_room_code, FIRST_ARENA_ROOM, LAST_ARENA_ROOM) then
        log.log_debug("enemies: arena room code must be from 1000 to 1999")
        return false
    end
    return true
end

local function check_kinds(kinds)
    if type(kinds) ~= "table" or #kinds == 0 then
        log.log_debug("enemies: kinds must be a list with at least one enemy kind")
        return false
    end
    for index = 1, #kinds do
        if not memory_values.is_whole_number(kinds[index], FIRST_ENEMY_KIND, LAST_ENEMY_KIND) then
            log.log_debug("enemies: enemy kind " .. index .. " must be a whole number from 1")
            return false
        end
    end
    return true
end

local function get_world_enemy_kinds(world_id, arena_room_code)
    if not check_world_and_arena(world_id, arena_room_code) then
        return nil
    end
    local kinds = {}
    for _, entry in ipairs(get_arena_entries(world_id, arena_room_code)) do
        kinds[#kinds + 1] = get_enemy_kind_from_name(read_name(ReadLong(entry + MANIFEST_NAME_OFFSET, true)))
    end
    return kinds
end

local function set_world_enemy_kinds(world_id, arena_room_code, kinds)
    if not check_world_and_arena(world_id, arena_room_code) then
        return false
    end
    if not check_kinds(kinds) then
        return false
    end
    if world_enemy_kinds[world_id] == nil then
        world_enemy_kinds[world_id] = {}
    end
    world_enemy_kinds[world_id][arena_room_code] = kinds
    return true
end

local function set_world_enemy_swaps(world_id, swaps)
    if not memory_values.is_whole_number(world_id, FIRST_WORLD, LAST_WORLD) or SWAP_ROOM_KINDS[world_id] == nil then
        log.log_debug("enemies: enemies can be swapped in worlds 1 to 9 and 11 to 13")
        return false
    end
    if type(swaps) ~= "table" then
        log.log_debug("enemies: swaps must be a list of {from, to}")
        return false
    end
    local new_kinds = {}
    local used = {}
    for index, swap in ipairs(swaps) do
        if type(swap) ~= "table" then
            log.log_debug("enemies: swap " .. index .. " must be a table")
            return false
        end
        if not memory_values.is_whole_number(swap.from, FIRST_ENEMY_KIND, LAST_HEARTLESS_KIND) or
            not memory_values.is_whole_number(swap.to, FIRST_ENEMY_KIND, LAST_HEARTLESS_KIND) then
            log.log_debug("enemies: swap " .. index .. " needs enemy kinds from 1 to 36")
            return false
        end
        if new_kinds[swap.from] ~= nil or used[swap.to] then
            log.log_debug("enemies: swap " .. index .. " uses an enemy kind twice")
            return false
        end
        new_kinds[swap.from] = swap.to
        used[swap.to] = true
    end
    world_swaps[world_id] = new_kinds
    return true
end

local function is_position_number(value)
    if type(value) ~= "number" then
        return false
    end
    return value >= -FARTHEST_POSITION and value <= FARTHEST_POSITION
end

local function is_position(position)
    if position == nil then
        return true
    end
    if type(position) ~= "table" then
        return false
    end
    return is_position_number(position.x) and is_position_number(position.y) and is_position_number(position.z)
end

local function set_boss_fight(world_id, arena_room_code, kind, variant, position)
    if not memory_values.is_whole_number(world_id, CASTLE_HALLS, LAST_WORLD) then
        log.log_debug("enemies: the world of a boss fight must be from 0 (Exit Hall) to 13")
        return false
    end
    if not memory_values.is_whole_number(arena_room_code, FIRST_ARENA_ROOM, LAST_ARENA_ROOM) then
        log.log_debug("enemies: arena room code must be from 1000 to 1999")
        return false
    end
    if not memory_values.is_whole_number(kind, FIRST_BOSS_KIND, LAST_BOSS_KIND) then
        log.log_debug("enemies: boss kind must be from 100 to 199")
        return false
    end
    if not memory_values.is_whole_number(variant, 0, LAST_BOSS_VARIANT) then
        log.log_debug("enemies: boss variant must be from 0 to 9")
        return false
    end
    if not is_position(position) then
        log.log_debug("enemies: a boss position needs x, y and z")
        return false
    end
    local fight = {}
    fight.position = position
    fight.world = world_id
    fight.arena = arena_room_code
    fight.kind = kind
    fight.variant = variant
    boss_fights[string.format("wo%02d%04d.esd", world_id, arena_room_code)] = fight
    return true
end

local function set_battle_formation(world_id, arena_room_code, formation, kinds)
    if not check_world_and_arena(world_id, arena_room_code) then
        return false
    end
    if not memory_values.is_whole_number(formation, 0, FORMATION_COUNT - 1) then
        log.log_debug("enemies: formation must be from 0 to 31")
        return false
    end
    if not check_kinds(kinds) then
        return false
    end
    local file_name = string.format("wo%02d%04d.esd", world_id, arena_room_code)
    if formation_changes[file_name] == nil then
        formation_changes[file_name] = {}
    end
    formation_changes[file_name][formation] = kinds
    return true
end

local function to_address(osd, value)
    if value < HANDLE_FLAG then
        return osd + value
    end
    local segment = math.floor((value - HANDLE_FLAG) / HANDLE_SEGMENT_SIZE) % HANDLE_SEGMENT_COUNT
    local offset = value % HANDLE_SEGMENT_SIZE
    local segment_base = ReadLong(handleSegmentTable + segment * POINTER_SIZE)
    if segment_base == 0 then
        return nil
    end
    return segment_base + offset
end

local function read_magic(address)
    local characters = {}
    for index = 0, 3 do
        characters[#characters + 1] = string.char(ReadByte(address + index, true))
    end
    return table.concat(characters)
end

local function find_first_osd(file_data)
    for _, offset in ipairs(FIRST_OSD_OFFSETS) do
        if read_magic(file_data + offset) == OSD_MAGIC then
            return file_data + offset
        end
    end
    return nil
end

local function find_second_osd(file_data, first_osd)
    local entry = file_data + (MAX_ARCHIVE_ENTRIES - 1) * ARCHIVE_ENTRY_SIZE
    if ReadByte(entry + ARCHIVE_NAME_OFFSET, true) == 0 then
        return nil
    end
    local osd = to_address(file_data, read_unsigned_int(entry))
    if osd == nil or osd <= first_osd or osd >= file_data + MAX_ARENA_FILE_SIZE then
        report_once("the second part of an arena file was not found")
        return nil
    end
    if read_magic(osd) ~= OSD_MAGIC then
        report_once("the second part of an arena file was not found")
        return nil
    end
    return osd
end

local function read_formation_waves(osd, formation)
    local block_value = read_unsigned_int(osd + OSD_FORMATIONS_OFFSET + formation * 4)
    if block_value == 0 then
        return nil
    end
    local block = to_address(osd, block_value)
    if block == nil then
        return nil
    end
    local waves = {}
    for slot = 0, SETS_PER_GROUP - 1 do
        local set_value = read_unsigned_int(block + (BATTLE_GROUP * SETS_PER_GROUP + slot) * 4)
        if set_value ~= 0 then
            local set = to_address(osd, set_value)
            if set ~= nil then
                local wave = {}
                wave.count = ReadInt(set + SET_COUNT_OFFSET, true)
                wave.records = to_address(osd, read_unsigned_int(set + SET_RECORDS_OFFSET))
                if wave.records ~= nil then
                    waves[#waves + 1] = wave
                end
            end
        end
    end
    return waves
end

local function get_battle_formation(world_id, arena_room_code, formation)
    if not check_world_and_arena(world_id, arena_room_code) then
        return nil
    end
    if not memory_values.is_whole_number(formation, 0, FORMATION_COUNT - 1) then
        return nil
    end
    local file_data = loaded_files.find_loaded_file(string.format("wo%02d%04d.esd", world_id, arena_room_code), ARENA_FILE_POOL)
    if file_data == nil then
        return nil
    end
    local osd = find_first_osd(file_data)
    if osd == nil then
        return nil
    end
    local waves = read_formation_waves(osd, formation)
    if waves == nil then
        return nil
    end
    local result = {}
    for _, wave in ipairs(waves) do
        local kinds = {}
        for index = 0, wave.count - 1 do
            kinds[#kinds + 1] = ReadShort(wave.records + index * RECORD_SIZE + RECORD_KIND_OFFSET, true)
        end
        result[#result + 1] = kinds
    end
    return result
end

local function apply_formation(osd, formation, kinds)
    local waves = read_formation_waves(osd, formation)
    if waves == nil then
        report_once("formation " .. formation .. " does not exist in an arena file that has changes")
        return
    end
    local record_number = 0
    for _, wave in ipairs(waves) do
        for index = 0, wave.count - 1 do
            local kind = kinds[(record_number % #kinds) + 1]
            memory_values.keep_short(wave.records + index * RECORD_SIZE + RECORD_KIND_OFFSET, kind)
            record_number = record_number + 1
        end
    end
end

local function apply_formations()
    if next(formation_changes) == nil then
        return
    end
    local arena_files = loaded_files.get_loaded_file_map(ARENA_FILE_POOL)
    for file_name, formations in pairs(formation_changes) do
        local file_data = arena_files[file_name]
        if file_data ~= nil then
            local osd = find_first_osd(file_data)
            if osd ~= nil then
                for formation, kinds in pairs(formations) do
                    apply_formation(osd, formation, kinds)
                end
            end
        end
    end
end

local function apply_world_enemy_kinds()
    if next(world_enemy_kinds) == nil then
        return
    end
    collect_kind_names()
    for world_id, arenas in pairs(world_enemy_kinds) do
        for arena_room_code, kinds in pairs(arenas) do
            local entries = get_arena_entries(world_id, arena_room_code)
            if #kinds > #entries then
                report_once(string.format("world %d arena %d loads %d enemy kinds, so %d kinds do not fit", world_id,
                    arena_room_code, #entries, #kinds))
            else
                for index = 1, #kinds do
                    local name_address = kind_names[kinds[index]]
                    if name_address == nil then
                        report_once("no world loads enemy kind " .. kinds[index] .. ", so it can not be added")
                    else
                        memory_values.keep_long(entries[index] + MANIFEST_NAME_OFFSET, name_address)
                    end
                end
            end
        end
    end
end

local function get_swapped_kind(swaps, kind)
    if swaps[kind] ~= nil then
        return swaps[kind]
    end
    return kind
end

local function apply_swap_entry(entry, wanted_kind)
    local current_kind = get_enemy_kind_from_name(read_name(ReadLong(entry + MANIFEST_NAME_OFFSET, true)))
    if current_kind == wanted_kind then
        return
    end
    local name_address = kind_names[wanted_kind]
    if name_address == nil then
        report_once("no world loads enemy kind " .. wanted_kind .. ", so it can not be added")
        return
    end
    memory_values.keep_long(entry + MANIFEST_NAME_OFFSET, name_address)
end

local function apply_swap_room(world_id, room_code, kinds, swaps)
    local entries = get_arena_entries(world_id, room_code)
    if #entries ~= #kinds then
        report_once(string.format("world %d room %d does not load the enemies it should", world_id, room_code))
        return
    end
    for index, kind in ipairs(kinds) do
        apply_swap_entry(entries[index], get_swapped_kind(swaps, kind))
    end
end

local function get_swap_world(file_name)
    local world_text, room_text = string.match(file_name, "^wo(%d%d)(%d%d%d%d)%.esd$")
    if world_text == nil then
        return nil
    end
    local room_code = tonumber(room_text)
    local is_field_room = room_code <= LAST_FIELD_ROOM
    local is_arena = room_code >= FIRST_SWAP_ARENA and room_code <= LAST_SWAP_ARENA
    local is_tutorial = tonumber(world_text) == TUTORIAL_WORLD and room_code == TUTORIAL_ARENA
    if not is_field_room and not is_arena and not is_tutorial then
        return nil
    end
    return tonumber(world_text)
end

local function swap_set(set, swaps, finished)
    local records = to_address(set.osd, read_unsigned_int(set.address + SET_RECORDS_OFFSET))
    if records == nil then
        return
    end
    for index = 0, ReadInt(set.address + SET_COUNT_OFFSET, true) - 1 do
        local kind_address = records + index * RECORD_SIZE + RECORD_KIND_OFFSET
        if not finished[kind_address] then
            finished[kind_address] = true
            memory_values.keep_short(kind_address, get_swapped_kind(swaps, ReadShort(kind_address, true)))
        end
    end
end

local function swap_formation(osd, formation, swaps, finished)
    local block_value = read_unsigned_int(osd + OSD_FORMATIONS_OFFSET + formation * 4)
    if block_value == 0 then
        return
    end
    local block = to_address(osd, block_value)
    if block == nil then
        return
    end
    for slot = 0, GROUP_COUNT * SETS_PER_GROUP - 1 do
        local set_value = read_unsigned_int(block + slot * 4)
        if set_value ~= 0 then
            local set = {osd = osd, address = to_address(osd, set_value)}
            if set.address ~= nil then
                swap_set(set, swaps, finished)
            end
        end
    end
end

local function apply_swap_file(file_data, swaps)
    local first_osd = find_first_osd(file_data)
    if first_osd == nil then
        return
    end
    if ReadByte(file_data + SWAP_MARK_OFFSET, true) == SWAP_MARK then
        return
    end
    local second_osd = find_second_osd(file_data, first_osd)
    local finished = {}
    for formation = 0, FORMATION_COUNT - 1 do
        swap_formation(first_osd, formation, swaps, finished)
        if second_osd ~= nil then
            swap_formation(second_osd, formation, swaps, finished)
        end
    end
    WriteByte(file_data + SWAP_MARK_OFFSET, SWAP_MARK, true)
end

local function is_any_kind_swapped(kinds)
    for _, swaps in pairs(world_swaps) do
        for _, kind in ipairs(kinds) do
            if swaps[kind] ~= nil then
                return true
            end
        end
    end
    return false
end

local function is_code_at(address, code)
    return ReadByte(address) == code[1] and ReadByte(address + 1) == code[2]
end

local function apply_room_prize_check(check)
    local address = heartlessDropCode + check.offset
    if not is_any_kind_swapped(check.kinds) or is_code_at(address, check.changed) then
        return
    end
    if not is_code_at(address, check.vanilla) then
        report_once("the " .. check.room .. " prize code is not where it should be")
        return
    end
    WriteByte(address, check.changed[1])
    WriteByte(address + 1, check.changed[2])
end

local function apply_room_prizes()
    for _, check in ipairs(ROOM_PRIZE_CHECKS) do
        apply_room_prize_check(check)
    end
end

local function apply_world_swaps()
    if next(world_swaps) == nil then
        return
    end
    apply_room_prizes()
    collect_kind_names()
    for world_id, swaps in pairs(world_swaps) do
        for room_code, kinds in pairs(SWAP_ROOM_KINDS[world_id]) do
            apply_swap_room(world_id, room_code, kinds, swaps)
        end
    end
    for _, file in ipairs(loaded_files.list_loaded_files(ARENA_FILE_POOL)) do
        local world_id = get_swap_world(string.lower(file.name))
        if world_id ~= nil and world_swaps[world_id] ~= nil and file.data ~= 0 then
            apply_swap_file(file.data, world_swaps[world_id])
        end
    end
end

local function apply_boss_manifest(fight)
    local entries = get_arena_entries(fight.world, fight.arena)
    if #entries == 0 then
        report_once(string.format("world %d arena %d loads no boss", fight.world, fight.arena))
        return
    end
    apply_swap_entry(entries[1], fight.kind)
end

local function keep_only_first_wave(osd)
    local block = to_address(osd, read_unsigned_int(osd + OSD_FORMATIONS_OFFSET + BOSS_FORMATION * 4))
    if block == nil then
        return
    end
    local first_set = nil
    for slot = 0, SETS_PER_GROUP - 1 do
        local slot_address = block + (BATTLE_GROUP * SETS_PER_GROUP + slot) * 4
        local set_value = read_unsigned_int(slot_address)
        if set_value ~= 0 then
            if first_set == nil then
                first_set = to_address(osd, set_value)
            else
                memory_values.keep_int(slot_address, 0)
            end
        end
    end
    if first_set ~= nil then
        memory_values.keep_int(first_set + SET_COUNT_OFFSET, ONE_BOSS)
        memory_values.keep_int(first_set + SET_MORE_WAVES_OFFSET, NO_MORE_WAVES)
    end
end

local function keep_float(address, value)
    if math.abs(ReadFloat(address, true) - value) > SMALLEST_MOVE then
        WriteFloat(address, value, true)
    end
end

local function apply_boss_position(record, position)
    if position == nil then
        return
    end
    keep_float(record, position.x)
    keep_float(record + POSITION_SIZE, position.y)
    keep_float(record + POSITION_SIZE * 2, position.z)
end

local function apply_boss_record(file_data, fight)
    local osd = find_first_osd(file_data)
    if osd == nil then
        return
    end
    local waves = read_formation_waves(osd, BOSS_FORMATION)
    if waves == nil or waves[1] == nil then
        report_once(string.format("world %d arena %d has no boss", fight.world, fight.arena))
        return
    end
    keep_only_first_wave(osd)
    apply_boss_position(waves[1].records, fight.position)
    memory_values.keep_short(waves[1].records + RECORD_KIND_OFFSET, fight.kind)
    memory_values.keep_int(waves[1].records + RECORD_VARIANT_OFFSET, fight.variant)
end

local function apply_boss_fights()
    if next(boss_fights) == nil then
        return
    end
    collect_kind_names()
    local arena_files = loaded_files.get_loaded_file_map(ARENA_FILE_POOL)
    for file_name, fight in pairs(boss_fights) do
        apply_boss_manifest(fight)
        if arena_files[file_name] ~= nil then
            apply_boss_record(arena_files[file_name], fight)
        end
    end
end

local function apply_enemies()
    apply_boss_fights()
    apply_world_swaps()
    apply_world_enemy_kinds()
    apply_formations()
end

return {
    get_world_enemy_kinds = get_world_enemy_kinds,
    set_world_enemy_kinds = set_world_enemy_kinds,
    set_world_enemy_swaps = set_world_enemy_swaps,
    set_boss_fight = set_boss_fight,
    get_battle_formation = get_battle_formation,
    set_battle_formation = set_battle_formation,
    apply_enemies = apply_enemies
}
