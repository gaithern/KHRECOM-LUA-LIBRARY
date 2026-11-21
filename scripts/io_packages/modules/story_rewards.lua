local cffi = require("cffi")
local native = require("helpers.native")
local call_redirect = require("helpers.call_redirect")

local GIVE_WITH_POPUP_FUNCTION_TYPE = "uint64_t (*)(uint64_t, uint64_t, uint64_t)"
local GIVE_FUNCTION_TYPE = "uint64_t (*)(uint64_t, uint64_t)"
local GIVE_SLEIGHT_FUNCTION_TYPE = "uint64_t (*)(uint64_t)"
local SKIPPED_RESULT = 1
local LOW_16_BITS = 65536

local REWARD_KINDS = {
    ITEM_WITH_POPUP = "item_with_popup",
    ITEM = "item",
    SLEIGHT = "sleight",
    BOSS_REWARD = "boss_reward",
    BATTLE_PICKUP = "battle_pickup"
}

local reward_handler = nil
local original_give_with_popup = nil
local original_give = nil
local original_give_sleight = nil

local function ask_handler(kind, id, value)
    if reward_handler == nil then
        return false
    end
    local ok, skip_vanilla = pcall(reward_handler, kind, id, value)
    if not ok then
        native.log_debug("story reward handler failed: " .. tostring(skip_vanilla))
        return false
    end
    return skip_vanilla == true
end

local function to_low_16_bits(value)
    return cffi.tonumber(value) % LOW_16_BITS
end

local function on_give_with_popup(item_id, value, mode)
    if ask_handler(REWARD_KINDS.ITEM_WITH_POPUP, to_low_16_bits(item_id), to_low_16_bits(value)) then
        return SKIPPED_RESULT
    end
    return original_give_with_popup(item_id, value, mode)
end

local function on_give(item_id, value)
    if ask_handler(REWARD_KINDS.ITEM, to_low_16_bits(item_id), to_low_16_bits(value)) then
        return SKIPPED_RESULT
    end
    return original_give(item_id, value)
end

local function on_boss_reward(item_id, value, mode)
    if ask_handler(REWARD_KINDS.BOSS_REWARD, to_low_16_bits(item_id), to_low_16_bits(value)) then
        return SKIPPED_RESULT
    end
    return original_give_with_popup(item_id, value, mode)
end

local function on_battle_pickup(item_id, value, mode)
    if ask_handler(REWARD_KINDS.BATTLE_PICKUP, to_low_16_bits(item_id), to_low_16_bits(value)) then
        return SKIPPED_RESULT
    end
    return original_give_with_popup(item_id, value, mode)
end

local function on_give_sleight(sleight_index)
    if ask_handler(REWARD_KINDS.SLEIGHT, to_low_16_bits(sleight_index), nil) then
        return SKIPPED_RESULT
    end
    return original_give_sleight(sleight_index)
end

local function install_hooks()
    if original_give_with_popup == nil then
        original_give_with_popup = cffi.cast(GIVE_WITH_POPUP_FUNCTION_TYPE, BASE_ADDR + giveItemWithPopupFunction)
        original_give = cffi.cast(GIVE_FUNCTION_TYPE, BASE_ADDR + giveItemFunction)
        original_give_sleight = cffi.cast(GIVE_SLEIGHT_FUNCTION_TYPE, BASE_ADDR + giveSleightFunction)
    end
    local with_popup_installed = call_redirect.redirect_call(eventGiveItemWithPopupCallSite, giveItemWithPopupFunction, GIVE_WITH_POPUP_FUNCTION_TYPE, on_give_with_popup)
    local give_installed = call_redirect.redirect_call(eventGiveItemCallSite, giveItemFunction, GIVE_FUNCTION_TYPE, on_give)
    local sleight_installed = call_redirect.redirect_call(eventGiveSleightCallSite, giveSleightFunction, GIVE_SLEIGHT_FUNCTION_TYPE, on_give_sleight)
    local boss_installed = call_redirect.redirect_call(bossRewardGiveJumpSite, giveItemWithPopupFunction, GIVE_WITH_POPUP_FUNCTION_TYPE, on_boss_reward)
    local battle_installed = call_redirect.redirect_call(battlePickupGiveJumpSite, giveItemWithPopupFunction, GIVE_WITH_POPUP_FUNCTION_TYPE, on_battle_pickup)
    if not boss_installed then
        native.log_debug("story rewards: could not hook the boss reward")
    end
    if not battle_installed then
        native.log_debug("story rewards: could not hook battle pickups")
    end
    if not with_popup_installed then
        native.log_debug("story rewards: could not hook the event give item with popup command")
    end
    if not give_installed then
        native.log_debug("story rewards: could not hook the event give item command")
    end
    if not sleight_installed then
        native.log_debug("story rewards: could not hook the event give sleight command")
    end
    return with_popup_installed and give_installed and sleight_installed and boss_installed and battle_installed
end

local function set_story_reward_handler(handler)
    reward_handler = handler
    if handler == nil then
        return true
    end
    return install_hooks()
end

return {
    REWARD_KINDS = REWARD_KINDS,
    set_story_reward_handler = set_story_reward_handler
}
