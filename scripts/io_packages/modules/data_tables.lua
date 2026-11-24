local log = require("helpers.log")
local memory_values = require("helpers.memory_values")
local loaded_files = require("modules.loaded_files")
local world_drops = require("modules.world_drops")
local moogle_shop = require("modules.moogle_shop")
local floor_layouts = require("modules.floor_layouts")
local event_rewards = require("modules.event_rewards")
local enemies = require("modules.enemies")
local enemy_stats = require("modules.enemy_stats")
local chest_rewards = require("modules.chest_rewards")
local card_sleights = require("modules.card_sleights")
local drop_unlocks = require("modules.drop_unlocks")
local card_odds = require("modules.card_odds")
local heartless_drops = require("modules.heartless_drops")
local world_order = require("modules.world_order")
local starting_deck = require("modules.starting_deck")

local BATTLE_CARD_FILE = "battlecardlist.bin"
local SLEIGHT_FILE = "stockskilllist.bin"
local STORY_DOOR_FILE = "rcnorma1.bin"

local ENEMY_PARAMETER_POOL = 21
local FRAMES_BETWEEN_CHECKS = 30
local FRAMES_BETWEEN_SLOW_CHECKS = 600
local SETTLE_FRAMES = 10
local ENEMY_MANIFESTS_FRAME = 0
local CHEST_REWARDS_FRAME = 1
local CARD_SLEIGHTS_FRAME = 2
local WORLD_ORDER_FRAME = 3
local HEARTLESS_DROPS_FRAME = 4
local ENEMY_STATS_FRAME = 5
local DATA_FILES_FRAME = 6
local FLOOR_LAYOUTS_FRAME = 7

local frame_count = 0
local frames_to_settle = 0

local ROW_SIZE = 0x10
local HIT_COUNT = 4
local CARD_CP_OFFSET = 0x0A
local FIRST_CARD = 0x01
local LAST_CARD = 0x7E
local FIRST_SLEIGHT = 0x01
local LAST_SLEIGHT = 0x95
local MAX_POWER = 65535
local MAX_CP = 255

local STORY_DOOR_ROW_COUNT_OFFSET = 0x06
local STORY_DOOR_FIRST_ROW_OFFSET = 0x08
local STORY_DOOR_ROW_SIZE = 0x74
local STORY_DOOR_FIRST_RECORD_OFFSET = 0x04
local STORY_DOOR_RECORD_SIZE = 0x1C
local STORY_DOOR_KEY_OFFSET = 0x00
local STORY_DOOR_STAGE_COUNT_OFFSET = 0x02
local STORY_DOOR_FIRST_STAGE_OFFSET = 0x04
local STORY_DOOR_STAGE_SIZE = 0x08
local STORY_DOOR_STAGE_KIND_OFFSET = 0x02
local STORY_DOOR_STAGE_COLOUR_OFFSET = 0x04
local STORY_DOOR_COUNT = 4
local MAX_STORY_DOOR_STAGES = 3
local FIRST_FLOOR = 1
local LAST_FLOOR = 15
local MAX_STAGE_VALUE = 99

local STORY_DOORS = {
    KEY_OF_BEGINNINGS = 1,
    KEY_OF_GUIDANCE = 2,
    KEY_TO_TRUTH = 3,
    KEY_TO_REWARDS = 4
}

local STORY_DOOR_KINDS = {
    ANY_VALUE = 0,
    AT_MOST = 1,
    AT_LEAST = 2,
    EQUAL = 3,
    TOTAL = 4
}

local STORY_DOOR_COLOURS = {
    ANY = 0,
    RED = 1,
    GREEN = 2,
    BLUE = 3
}

local card_cp_changes = {}
local card_power_changes = {}
local sleight_power_changes = {}
local story_door_changes = {}
local all_story_doors_key_only = false

local function get_card_stats(card_id)
    if not memory_values.is_whole_number(card_id, FIRST_CARD, LAST_CARD) then
        return nil
    end
    local file_data = loaded_files.find_loaded_file(BATTLE_CARD_FILE)
    if file_data == nil then
        return nil
    end
    local row_address = file_data + card_id * ROW_SIZE
    local stats = {}
    stats.powers = {}
    for hit = 1, HIT_COUNT do
        stats.powers[hit] = ReadShort(row_address + (hit - 1) * 2, true)
    end
    stats.cp = ReadByte(row_address + CARD_CP_OFFSET, true)
    return stats
end

local function set_card_cp(card_id, cp)
    if not memory_values.is_whole_number(card_id, FIRST_CARD, LAST_CARD) then
        log.log_debug("data tables: card id must be from 0x01 to 0x7E")
        return false
    end
    if not memory_values.is_whole_number(cp, 0, MAX_CP) then
        log.log_debug("data tables: card CP must be from 0 to 255")
        return false
    end
    card_cp_changes[card_id] = cp
    return true
end

local function set_card_power(card_id, hit, power)
    if not memory_values.is_whole_number(card_id, FIRST_CARD, LAST_CARD) then
        log.log_debug("data tables: card id must be from 0x01 to 0x7E")
        return false
    end
    if not memory_values.is_whole_number(hit, 1, HIT_COUNT) then
        log.log_debug("data tables: hit must be from 1 to 4")
        return false
    end
    if not memory_values.is_whole_number(power, 0, MAX_POWER) then
        log.log_debug("data tables: power must be from 0 to 65535")
        return false
    end
    if card_power_changes[card_id] == nil then
        card_power_changes[card_id] = {}
    end
    card_power_changes[card_id][hit] = power
    return true
end

local function get_sleight_stats(sleight_id)
    if not memory_values.is_whole_number(sleight_id, FIRST_SLEIGHT, LAST_SLEIGHT) then
        return nil
    end
    local file_data = loaded_files.find_loaded_file(SLEIGHT_FILE)
    if file_data == nil then
        return nil
    end
    local row_address = file_data + sleight_id * ROW_SIZE
    local stats = {}
    stats.powers = {}
    for hit = 1, HIT_COUNT do
        stats.powers[hit] = ReadShort(row_address + (hit - 1) * 2, true)
    end
    return stats
end

local function set_sleight_power(sleight_id, hit, power)
    if not memory_values.is_whole_number(sleight_id, FIRST_SLEIGHT, LAST_SLEIGHT) then
        log.log_debug("data tables: sleight id must be from 0x01 to 0x95")
        return false
    end
    if not memory_values.is_whole_number(hit, 1, HIT_COUNT) then
        log.log_debug("data tables: hit must be from 1 to 4")
        return false
    end
    if not memory_values.is_whole_number(power, 0, MAX_POWER) then
        log.log_debug("data tables: power must be from 0 to 65535")
        return false
    end
    if sleight_power_changes[sleight_id] == nil then
        sleight_power_changes[sleight_id] = {}
    end
    sleight_power_changes[sleight_id][hit] = power
    return true
end

local function find_story_door_row(file_data, floor_number)
    local row_count = memory_values.read_signed_short(file_data + STORY_DOOR_ROW_COUNT_OFFSET)
    for row_number = 0, row_count - 1 do
        local row_address = file_data + STORY_DOOR_FIRST_ROW_OFFSET + row_number * STORY_DOOR_ROW_SIZE
        if memory_values.read_signed_short(row_address) == floor_number then
            return row_address
        end
    end
    return nil
end

local function get_story_door_record(file_data, floor_number, door_number)
    local row_address = find_story_door_row(file_data, floor_number)
    if row_address == nil then
        return nil
    end
    return row_address + STORY_DOOR_FIRST_RECORD_OFFSET + (door_number - 1) * STORY_DOOR_RECORD_SIZE
end

local function get_story_door_requirement(floor_number, door_number)
    if not memory_values.is_whole_number(floor_number, FIRST_FLOOR, LAST_FLOOR) then
        return nil
    end
    if not memory_values.is_whole_number(door_number, 1, STORY_DOOR_COUNT) then
        return nil
    end
    local file_data = loaded_files.find_loaded_file(STORY_DOOR_FILE)
    if file_data == nil then
        return nil
    end
    local record = get_story_door_record(file_data, floor_number, door_number)
    if record == nil then
        return nil
    end
    local requirement = {}
    requirement.key_index = memory_values.read_signed_short(record + STORY_DOOR_KEY_OFFSET)
    requirement.stages = {}
    local stage_count = memory_values.read_signed_short(record + STORY_DOOR_STAGE_COUNT_OFFSET)
    for stage_number = 1, stage_count do
        local stage_address = record + STORY_DOOR_FIRST_STAGE_OFFSET + (stage_number - 1) * STORY_DOOR_STAGE_SIZE
        local stage = {}
        stage.value = memory_values.read_signed_short(stage_address)
        stage.kind = memory_values.read_signed_short(stage_address + STORY_DOOR_STAGE_KIND_OFFSET)
        stage.colour = memory_values.read_signed_short(stage_address + STORY_DOOR_STAGE_COLOUR_OFFSET)
        requirement.stages[stage_number] = stage
    end
    return requirement
end

local function check_story_door_stages(stages)
    if type(stages) ~= "table" or #stages > MAX_STORY_DOOR_STAGES then
        log.log_debug("data tables: story door stages must be a list of at most 3 stages")
        return false
    end
    for index, stage in ipairs(stages) do
        if type(stage) ~= "table" then
            log.log_debug("data tables: story door stage " .. index .. " must be a table")
            return false
        end
        if not memory_values.is_whole_number(stage.value, 0, MAX_STAGE_VALUE) then
            log.log_debug("data tables: story door stage " .. index .. " value must be from 0 to 99")
            return false
        end
        if not memory_values.is_whole_number(stage.kind, STORY_DOOR_KINDS.ANY_VALUE, STORY_DOOR_KINDS.TOTAL) then
            log.log_debug("data tables: story door stage " .. index .. " kind must be one of STORY_DOOR_KINDS")
            return false
        end
        if not memory_values.is_whole_number(stage.colour, STORY_DOOR_COLOURS.ANY, STORY_DOOR_COLOURS.BLUE) then
            log.log_debug("data tables: story door stage " .. index .. " colour must be one of STORY_DOOR_COLOURS")
            return false
        end
    end
    return true
end

local function set_story_door_requirement(floor_number, door_number, stages)
    if not memory_values.is_whole_number(floor_number, FIRST_FLOOR, LAST_FLOOR) then
        log.log_debug("data tables: floor number must be from 1 to 15")
        return false
    end
    if not memory_values.is_whole_number(door_number, 1, STORY_DOOR_COUNT) then
        log.log_debug("data tables: door number must be one of STORY_DOORS")
        return false
    end
    if not check_story_door_stages(stages) then
        return false
    end
    if story_door_changes[floor_number] == nil then
        story_door_changes[floor_number] = {}
    end
    story_door_changes[floor_number][door_number] = stages
    return true
end

local function set_story_doors_key_only()
    all_story_doors_key_only = true
end

local function apply_card_stats(file_data)
    for card_id, cp in pairs(card_cp_changes) do
        memory_values.keep_byte(file_data + card_id * ROW_SIZE + CARD_CP_OFFSET, cp)
    end
    for card_id, powers in pairs(card_power_changes) do
        for hit, power in pairs(powers) do
            memory_values.keep_short(file_data + card_id * ROW_SIZE + (hit - 1) * 2, power)
        end
    end
end

local function apply_sleight_stats(file_data)
    for sleight_id, powers in pairs(sleight_power_changes) do
        for hit, power in pairs(powers) do
            memory_values.keep_short(file_data + sleight_id * ROW_SIZE + (hit - 1) * 2, power)
        end
    end
end

local function write_story_door_stages(record, stages)
    for stage_number, stage in ipairs(stages) do
        local stage_address = record + STORY_DOOR_FIRST_STAGE_OFFSET + (stage_number - 1) * STORY_DOOR_STAGE_SIZE
        memory_values.keep_short(stage_address, stage.value)
        memory_values.keep_short(stage_address + STORY_DOOR_STAGE_KIND_OFFSET, stage.kind)
        memory_values.keep_short(stage_address + STORY_DOOR_STAGE_COLOUR_OFFSET, stage.colour)
    end
    memory_values.keep_short(record + STORY_DOOR_STAGE_COUNT_OFFSET, #stages)
end

local function apply_story_doors(file_data)
    for floor_number = FIRST_FLOOR, LAST_FLOOR do
        for door_number = 1, STORY_DOOR_COUNT do
            local stages = nil
            if all_story_doors_key_only then
                stages = {}
            end
            if story_door_changes[floor_number] ~= nil and story_door_changes[floor_number][door_number] ~= nil then
                stages = story_door_changes[floor_number][door_number]
            end
            if stages ~= nil then
                local record = get_story_door_record(file_data, floor_number, door_number)
                if record ~= nil then
                    write_story_door_stages(record, stages)
                end
            end
        end
    end
end

local function apply_data_files(file_map)
    local battle_card_file = file_map[BATTLE_CARD_FILE]
    if battle_card_file ~= nil then
        apply_card_stats(battle_card_file)
    end
    local sleight_file = file_map[SLEIGHT_FILE]
    if sleight_file ~= nil then
        apply_sleight_stats(sleight_file)
    end
    local story_door_file = file_map[STORY_DOOR_FILE]
    if story_door_file ~= nil then
        apply_story_doors(story_door_file)
    end
    card_odds.apply_card_odds(file_map)
end

local function is_frame_due(frames_between, frame_number)
    return frame_count % frames_between == frame_number
end

local function update_frames_to_settle()
    if loaded_files.did_files_change(loaded_files.DATA_FILE_POOL) then
        frames_to_settle = SETTLE_FRAMES
    elseif frames_to_settle > 0 then
        frames_to_settle = frames_to_settle - 1
    end
end

local function apply_loaded_tables(file_map)
    moogle_shop.apply_moogle_shop(file_map)
    world_drops.apply_world_drops(file_map)
    starting_deck.apply_starting_deck(file_map)
    if frames_to_settle > 0 or is_frame_due(FRAMES_BETWEEN_CHECKS, DATA_FILES_FRAME) then
        apply_data_files(file_map)
    end
    if frames_to_settle > 0 or is_frame_due(FRAMES_BETWEEN_SLOW_CHECKS, FLOOR_LAYOUTS_FRAME) then
        floor_layouts.apply_floor_layouts(file_map)
    end
end

local function apply_enemy_files()
    local enemies_changed = loaded_files.did_files_change(ENEMY_PARAMETER_POOL)
    if enemies_changed or is_frame_due(FRAMES_BETWEEN_CHECKS, ENEMY_STATS_FRAME) then
        enemy_stats.apply_enemy_stats()
    end
    local check_drops = enemies_changed or is_frame_due(FRAMES_BETWEEN_CHECKS, HEARTLESS_DROPS_FRAME)
    heartless_drops.apply_heartless_drops(check_drops)
    enemies.apply_enemies(is_frame_due(FRAMES_BETWEEN_SLOW_CHECKS, ENEMY_MANIFESTS_FRAME))
end

local function apply_game_code()
    if is_frame_due(FRAMES_BETWEEN_CHECKS, CHEST_REWARDS_FRAME) then
        chest_rewards.apply_chest_rewards()
    end
    if is_frame_due(FRAMES_BETWEEN_CHECKS, CARD_SLEIGHTS_FRAME) then
        card_sleights.apply_card_sleights()
        drop_unlocks.apply_drop_unlocks()
    end
    if is_frame_due(FRAMES_BETWEEN_CHECKS, WORLD_ORDER_FRAME) then
        world_order.apply_world_order()
    end
end

local function update_data_tables()
    loaded_files.start_update()
    update_frames_to_settle()
    apply_loaded_tables(loaded_files.get_loaded_file_map())
    event_rewards.apply_event_rewards()
    apply_enemy_files()
    apply_game_code()
    loaded_files.finish_update()
    frame_count = frame_count + 1
end

return {
    STORY_DOORS = STORY_DOORS,
    STORY_DOOR_KINDS = STORY_DOOR_KINDS,
    STORY_DOOR_COLOURS = STORY_DOOR_COLOURS,
    get_card_stats = get_card_stats,
    set_card_cp = set_card_cp,
    set_card_power = set_card_power,
    get_sleight_stats = get_sleight_stats,
    set_sleight_power = set_sleight_power,
    get_story_door_requirement = get_story_door_requirement,
    set_story_door_requirement = set_story_door_requirement,
    set_story_doors_key_only = set_story_doors_key_only,
    update_data_tables = update_data_tables
}
