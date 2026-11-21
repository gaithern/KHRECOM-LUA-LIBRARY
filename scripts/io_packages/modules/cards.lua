local VALUES_PER_CARD = 10
local FIRST_PREMIUM_VALUE = 10
local LAST_PREMIUM_VALUE = 19
local LAST_CARD_WITH_PREMIUM = 80
local LAST_CARD_WITH_LARGE_PREMIUM_OFFSET = 24
local LARGE_PREMIUM_OFFSET = 0xF0
local SMALL_PREMIUM_OFFSET = 0xA0
local BYTES_PER_DECK_ENTRY = 4

local function get_battle_card_slot(card_index, card_value)
    local normal_value = card_value % VALUES_PER_CARD
    local slot = ((card_index - 1) * VALUES_PER_CARD) + 1 + normal_value
    if slot > PLAYER_DATA_BATTLE_CARDS_SIZE then
        return nil
    end

    if card_index > LAST_CARD_WITH_PREMIUM and card_value >= FIRST_PREMIUM_VALUE then
        card_value = normal_value
    end

    if card_value >= 0 and card_value < VALUES_PER_CARD then
        return slot
    end

    local is_premium_value = card_value >= FIRST_PREMIUM_VALUE and card_value <= LAST_PREMIUM_VALUE
    if not is_premium_value then
        return nil
    end

    local premium_slot = slot + SMALL_PREMIUM_OFFSET
    if card_index <= LAST_CARD_WITH_LARGE_PREMIUM_OFFSET then
        premium_slot = slot + LARGE_PREMIUM_OFFSET
    end
    if premium_slot > PLAYER_DATA_BATTLE_CARDS_SIZE then
        return nil
    end
    return premium_slot
end

local function get_empty_battle_card_inventory()
    local inventory = {}
    for slot = 1, PLAYER_DATA_BATTLE_CARDS_SIZE do
        inventory[slot] = 0
    end
    return inventory
end

local function add_battle_card(inventory, card_index, card_value)
    local slot = get_battle_card_slot(card_index, card_value)
    if slot == nil then
        return false
    end
    inventory[slot] = inventory[slot] + 1
    return true
end

local function build_deck_bytes(deck_entries)
    local deck_bytes = {}
    for entry_number = 1, PLAYER_DATA_DECK_CARD_COUNT do
        local entry = deck_entries[entry_number]
        local first_byte = ((entry_number - 1) * BYTES_PER_DECK_ENTRY) + 1
        if entry == nil then
            deck_bytes[first_byte] = 0
            deck_bytes[first_byte + 1] = 0
            deck_bytes[first_byte + 2] = 0
            deck_bytes[first_byte + 3] = 0
        else
            deck_bytes[first_byte] = entry.card_id
            deck_bytes[first_byte + 1] = entry.premium
            deck_bytes[first_byte + 2] = entry.value
            deck_bytes[first_byte + 3] = entry.flags
        end
    end
    return deck_bytes
end

return {
    get_battle_card_slot = get_battle_card_slot,
    get_empty_battle_card_inventory = get_empty_battle_card_inventory,
    add_battle_card = add_battle_card,
    build_deck_bytes = build_deck_bytes
}
