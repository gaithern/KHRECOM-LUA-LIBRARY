local log = require("helpers.log")
local loaded_files = require("modules.loaded_files")
local world_order = require("modules.world_order")

local TRAVERSE_TOWN = 1
local DONALD_AND_GOOFY = 3
local DONALD_AND_GOOFY_RANGE = 4
local EXIT_HALLS_BEFORE_FLOOR_11 = 10

local join_early = false

local function set_donald_and_goofy_join_early(wanted)
    if type(wanted) ~= "boolean" then
        log.log_debug("friends: wanted must be true or false")
        return false
    end
    join_early = wanted
    return true
end

local function get_friend_flag_address()
    if ReadLong(timePlayedPointer) == 0 then
        return nil
    end
    local variables_address = ReadLong(GetPointer(timePlayedPointer, TIME_PLAYED_FIRST_OFFSET), true)
    if variables_address == 0 then
        return nil
    end
    return variables_address + TIME_PLAYED_SECOND_OFFSET + TIME_PLAYED_FRIEND_FLAG
end

local function should_have_joined()
    if not world_order.is_sora_story() or ReadLong(playerDataPointer) == 0 then
        return false
    end
    local world_id = loaded_files.find_loaded_drop_world()
    if world_id == nil or world_id <= TRAVERSE_TOWN then
        return false
    end
    local exit_halls_cleared = ReadByte(GetPointer(playerDataPointer, PLAYER_DATA_STORY_PROGRESS), true)
    return exit_halls_cleared < EXIT_HALLS_BEFORE_FLOOR_11
end

local function apply_friends()
    if not join_early or not should_have_joined() then
        return
    end
    local address = get_friend_flag_address()
    if address == nil then
        return
    end
    local flags = ReadByte(address, true)
    local donald_and_goofy = flags % DONALD_AND_GOOFY_RANGE
    if donald_and_goofy ~= DONALD_AND_GOOFY then
        WriteByte(address, flags - donald_and_goofy + DONALD_AND_GOOFY, true)
    end
end

return {
    set_donald_and_goofy_join_early = set_donald_and_goofy_join_early,
    apply_friends = apply_friends
}
