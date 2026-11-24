# KHRECOM Lua Library

A shared Lua library of helper functions for reading and writing Kingdom Hearts Re:Chain of Memories (PC)
memory, for use in the [Archipelago integration](https://github.com/gaithern/KH-RECOM-AP-LUA) and other
[LuaBackend](https://github.com/Sirius902/LuaBackend) mods. Supports both the Steam and EGS builds.
Modeled on [KH1-LUA-LIBRARY](https://github.com/gaithern/KH1-LUA-LIBRARY).

## Repository Layout

- `scripts/io_packages/*`

  | File | Description |
  | :--- | :---------- |
  | `VersionCheck.lua` | Detects the EGS or Steam build, then loads that build's address file and `memory_locations.lua`. Sets `canExecute` and `gameVersionName`. |
  | `EGSGlobal.lua` | Addresses (RVAs) for the Epic Games Store build. |
  | `SteamGlobal.lua` | Addresses (RVAs) for the Steam build. |
  | `memory_locations.lua` | Named offsets from the base pointers in the version files, plus table sizes. Shared by both builds. |
  | `khrecom_lua_library.lua` | Main script to be used by outside mods. Contains callers for all functionality. |
  | `helpers/bits.lua` | Bit and list helpers. |
  | `modules/cards.lua` | Battle card inventory slots and deck byte layout. |
  | `modules/exe_tables.lua` | Static tables inside the game exe: level-up sleights, boss rewards, world select offers, EXP gems. |
  | `modules/card_ids.lua` | Named IDs for every card, grouped by card type. |
  | `modules/sleight_ids.lua` | Named game indices for every sleight Sora can get. |
  | `json.lua` | Generic lua helper. From [RXI's json.lua](https://github.com/rxi/json.lua). |
- `build.py`
  - Creates `mod.yml` by calling `generate_mod_yml.py`.
- `generate_mod_yml.py`
  - Generates `mod.yml` from the files under `scripts/`.
- `mod.yml`
  - OpenKH configuration file listing the files to ship.

## Building mod/making changes
After changing scripts, run `python build.py` to regenerate `mod.yml`.

## Using the library

```lua
local khrecom = require("khrecom_lua_library")

function _OnInit()
    if GAME_ID == 0x9E3134F5 and ENGINE_TYPE == "BACKEND" then
        require("VersionCheck")
    else
        ConsolePrint("RE:CoM not detected, not running script")
    end
end

function _OnFrame()
    if not canExecute then
        return
    end
    if khrecom.get_time_played() > 0 then
        ConsolePrint("Sora is level " .. khrecom.get_soras_level())
    end
end
```

`require("khrecom_lua_library")` can happen at the top of a script. The address globals it uses are only read
when a function is called, which is after `VersionCheck` has run.

## Address status

Most addresses come from KH-RECOM-AP-LUA, which has used them in play on both builds. These ones have not been
checked in game yet:

| Address | Build | Why it is unverified |
| :------ | :---- | :------------------- |
| `soraControlPointer`, `soraDeathPointer` | EGS | Worked out from the Steam values using the 0x600 gap every other pointer pair has. The old DeathLink script was Steam only. |
| `watchedDaysFlag` | Steam | Worked out from the EGS value the same way. The old Days script was EGS only. |
| `expGemTable` | both | Both builds use the same address, unlike every other table. One of them is probably wrong. |
| `bossRewardTable` | both | Taken from the exe research sheets. Not yet read or written by any script. |
| `worldSelect*Table` | both | Found in the exe code on both builds. Not yet written in game, so whether the screen picks up a change mid-game is untested. |
| Floor rooms (`floorState*`, `floorRoom*`, `createRoomFunction`, `mapCardToRoomCodeFunction`, `getFloorWorldFunction`) | EGS | Making a whole floor's rooms while outside the floor was tested in game on Steam. The EGS addresses were found by matching the Steam code bytes. |
| Data tables (`loadedFilePoolTable`, `moogleFallback*`) | EGS | Tested in game on Steam. The EGS pool table was read from the EGS lookup code; the EGS fallback card addresses were found by matching the Steam code bytes. |
| Decks 2 and 3 | both | Deck 1 is at `-0x8D8` and deck 3 at `-0x5C0`, so decks are `0x18C` bytes apart. Deck 2 is inferred from that. |

## Currently shipped functions
All functions below are available on the table returned by `require("khrecom_lua_library")`.

### Helpers
| Function | Arguments | Returns | Description |
| :------- | :-------- | :------ | :---------- |
| `byte_to_bits` | `byte` | array of 8 bits | Converts a byte to an array of 8 bits (LSB first). |
| `bits_to_byte` | `bits` | byte | Converts an array of 8 bits (LSB first) back to a byte. |
| `ReadBits` | `address, absolute` | array of 8 bits | Reads the byte at `address` and returns it as a bit array. |
| `ReadBit` | `address, bit_number, absolute` | `0` or `1` | Reads one bit (1-based) from the byte at `address`. |
| `WriteBit` | `address, bit_number, value, absolute` | none | Writes one bit (1-based) into the byte at `address`. |
| `contains` | `list, value` | boolean | Returns true if `value` is in `list`. |
| `get_sleight_count` | none | number | Number of sleight flags `set_sleights_obtained` expects (84). |

### Getters
| Function | Arguments | Returns | Description |
| :------- | :-------- | :------ | :---------- |
| `get_current_floor` | none | byte | Current Castle Oblivion floor. |
| `get_current_room` | none | u16 | Current room ID. |
| `get_current_world` | none | byte | Current world ID. |
| `get_time_played` | none | int | Play time counter. 0 before a save is loaded. |
| `get_journal_cards_found` | none | 108 bytes | Journal card-found array. |
| `get_heartless_defeated` | none | 31 numbers | Defeat count for each heartless in journal order. |
| `get_rooms_opened` | none | 39 bytes | 13 floors x 3 story rooms (Beginnings, Guidance, Truth). |
| `get_world_assignments` | none | 13 bytes | World ID assigned to each floor. |
| `get_friend_cards` | none | 8 bytes | Donald, Goofy, Aladdin, Ariel, Jack, Peter Pan, Beast, Pluto. |
| `get_rewards_bounties` | none | 46 bytes | Rewards and bounties obtained. |
| `get_minigames_cleared` | none | 6 bytes | 100 Acre Wood minigames cleared. |
| `get_world_journal_entries` | none | 13 bytes | World journal entries. |
| `get_exit_hall_events` | none | 48 bytes | 24 u16 Exit Hall event IDs. |
| `get_story_progress` | none | byte | Number of Exit Halls cleared. |
| `get_soras_level` | none | int | Sora's level. |
| `get_attack_power` | none | int | Sora's attack power (default 10). |
| `get_moogle_points` | none | int | Sora's Moogle points (0-99999). |
| `get_journal_world_value` | none | u16 | World value the AP Exit Hall fix checks. |
| `is_piglet_found` | none | boolean | Whether Piglet has been found. |
| `get_battle_card_inventory` | none | 870 bytes | 87 cards x 10 values. |
| `get_enemy_card_inventory` | none | 57 bytes | Enemy card counts. |
| `get_map_card_inventory` | none | 240 bytes | 24 map cards x 10 values. |
| `get_deck` | `deck_number` | 396 bytes | 99 entries of `{card_id, premium, value, flags}`. |
| `get_gold_map_cards` | none | 4 bytes | Beginnings, Guidance, Truth, Rewards. |
| `get_watched_days` | none | byte | Watched 358/2 Days flag. |
| `is_sora_loaded` | none | boolean | Whether Sora's control data exists. |
| `get_sora_hp` | none | int or nil | Sora's HP, or nil when Sora is not loaded. |

### Setters
| Function | Arguments | Returns | Description |
| :------- | :-------- | :------ | :---------- |
| `set_battle_card_inventory` | `inventory` | none | Writes all 870 battle card counts. |
| `set_enemy_card_inventory` | `inventory` | none | Writes all 57 enemy card counts. |
| `set_map_card_inventory` | `inventory` | none | Writes all 240 map card counts. |
| `set_deck` | `deck_number, deck_bytes` | none | Writes a deck. Build `deck_bytes` with `build_deck_bytes`. |
| `set_sleights_obtained` | `sleight_flags` | none | Takes 84 flags (1 = obtained) in AP order and packs them into the 21-byte bitfield. |
| `set_gold_map_cards` | `gold_map_cards` | none | Writes the 4 gold map card flags. |
| `set_world_assignments` | `world_assignments` | none | Writes the world ID for each floor. |
| `set_world_journal_entries` | `entries` | none | Writes the 13 world journal entries. |
| `set_exit_hall_events` | `events` | none | Writes the 48-byte Exit Hall event array. |
| `set_story_progress` | `story_progress` | none | Sets the number of Exit Halls cleared. |
| `set_attack_power` | `attack_power` | none | Sets Sora's attack power. |
| `set_moogle_points` | `moogle_points` | none | Sets Sora's Moogle points, clamped to 0-99999. Writes the real total in Sora's stats block and the player data copy the shop shows. |
| `set_journal_card_found` | `card_number, value` | none | Writes one entry of the journal card-found array. |
| `set_friend_flag` | `value` | none | Writes the friend flag next to the play time counter. |
| `set_watched_days` | `value` | none | Writes the Watched 358/2 Days flag. |

### Actions
| Function | Arguments | Returns | Description |
| :------- | :-------- | :------ | :---------- |
| `ko_sora` | none | boolean | Knocks Sora out. Returns false when Sora is not loaded or is already going down. |

### Cards
| Function | Arguments | Returns | Description |
| :------- | :-------- | :------ | :---------- |
| `get_battle_card_slot` | `card_index, card_value` | number or nil | Slot in the battle card inventory for a card and value. Values 10-19 are premium. |
| `get_empty_battle_card_inventory` | none | 870 zeros | A blank inventory to fill. |
| `add_battle_card` | `inventory, card_index, card_value` | boolean | Adds one card to an inventory table. False when the card has no slot. |
| `build_deck_bytes` | `deck_entries` | 396 bytes | Turns a list of `{card_id, premium, value, flags}` tables into deck bytes, padding to 99 entries. |

### Exe tables
| Function | Arguments | Returns | Description |
| :------- | :-------- | :------ | :---------- |
| `get_level_up_sleight_count` | none | number | Number of level-up sleight slots (12). |
| `get_level_up_sleight` | `slot` | `level, sleight` | Reads one level-up sleight slot. |
| `set_level_up_sleight` | `slot, level, sleight` | none | Writes one level-up sleight slot. |
| `disable_level_up_sleights` | none | none | Sets every slot's level to 101 so no sleight is given on level up. |
| `get_boss_reward` | `record_number` | `{boss_id, card_type, card_number}` | Reads one of the 27 boss reward records. |
| `set_boss_reward` | `record_number, card_type, card_number` | none | Changes the card a boss gives. |
| `get_world_select_card` | `floor_group, story, slot` | u16 or nil | Reads one world the world-select screen can offer. See [World select tables](#world-select-tables). |
| `set_world_select_card` | `floor_group, story, slot, world_id` | boolean | Changes one offered world. False when the group or slot does not exist. |
| `get_world_select_cards` | `floor_group, story` | list of u16 | Reads every slot of one group for one story. |
| `get_exp_gem_divisor` | `gem_number` | int | Reads one of the 7 EXP gem divisors. |
| `set_exp_gem_divisor` | `gem_number, divisor` | none | Writes one EXP gem divisor. |

### Card IDs
One ID numbers every card in the game. The same number is the item ID the game's give functions take, the
`card_index` in [Cards](#cards), and the `card_id` in a deck entry. The tables come from the exe's item table (EGS
`0x59F4A0`, Steam `0x59F2E0`): 16 bytes per ID, `0x01`-`0xCA`, with a type byte first and a pointer to the
card's name at `+0x08`. The key names below are those names.

| Table | IDs | Contents |
| :---- | :-- | :------- |
| `ATTACK_CARDS` | `0x01`-`0x18` | Keyblades, from `KINGDOM_KEY` to `BOND_OF_FLAME` |
| `MAGIC_CARDS` | `0x1A`-`0x20` | `FIRE`, `BLIZZARD`, `THUNDER`, `CURE`, `GRAVITY`, `STOP`, `AERO` |
| `SUMMON_CARDS` | `0x23`-`0x29` | `SIMBA` to `CLOUD` |
| `ITEM_CARDS` | `0x2A`-`0x30` | `POTION` to `MEGALIXIR` |
| `FRIEND_CARDS` | `0x31`-`0x39` | `DONALD_DUCK` to `PLUTO` |
| `ENEMY_CARDS` | `0x44`-`0x80` | Heartless, bosses and Organization members, plus `GOLD_CARD`, `PLATINUM_CARD`, `CARD_SOLDIER_SPADE`, `CARD_SOLDIER_HEART` |
| `MAP_CARDS` | `0xA1`-`0xB9` | Red, green and blue map cards, from `TRANQUIL_DARKNESS` to `RANDOM_JOKER` |
| `KEY_CARDS` | `0xBA`-`0xBD` | `KEY_OF_BEGINNINGS`, `KEY_OF_GUIDANCE`, `KEY_TO_TRUTH`, `KEY_TO_REWARDS` |
| `WORLD_CARDS` | `0xBE`-`0xCA` | `TRAVERSE_TOWN` to `CASTLE_OBLIVION` (`100 Acre Wood` is `HUNDRED_ACRE_WOOD`) |
| `BUMBLE_RUMBLE_CARDS` | `0x19`, `0x21`, `0x22`, `0x9F` | 100 Acre Wood minigame cards: `KEYBLADE`, `WIND`, `HUNNY`, `BEE` |
| `GIMMICK_CARDS` | `0x3A`-`0x41` | Boss gimmick cards, from `GUARD_ARMOR` to `DARKSIDE` |
| `BOSS_ATTACK_CARDS` | `0x42`-`0x43` | `REPLIKU_SOUL_EATER`, `ZEXION` |
| `SPECIAL_CARDS` | `0xA0` | `RELOAD` |
| `PLACEHOLDER_CARD` | `0x3A` | Not a table: Guard Armor's gimmick card, which only says "Gimmick". |

`BUMBLE_RUMBLE_CARDS`, `GIMMICK_CARDS`, `BOSS_ATTACK_CARDS` and `SPECIAL_CARDS` have no English name in the item
table ("-", the boss's name, or an internal Japanese name); they were identified by showing each one with
a popup test in game on Steam. `0x81`-`0x9E` are left out: their internal Japanese names are boss names with
letters (Cloud A-B, Hades A-B, Hook A-D, Axel A-B, Larxene A-C, Riku A-D, Vexen A-B, Marluxia A-C, 2 and 3,
Lexaeus A-C, Ansem A-B, Zexion A), probably cards bosses use in battle, and the popup has no picture for them: it
shows a plain Keyblade card with a red frame (type `0x17`) or a blue one (type `0x27`). Every other ID from `0x01` to
`0xCA` shows a real card, so there is no blank card to use as a placeholder.

### Sleight IDs
`SLEIGHTS` names every sleight Sora can get, using the game's sleight index (the number the
journal sleight functions take), for example `khrecom.SLEIGHTS.SLIDING_DASH` (`0x04`) to
`khrecom.SLEIGHTS.LUCKY_BOUNTY_LV3` (`0x56`). Sleight names are not in the exe, so the table was generated from the
apworld's `Data/items.csv`: the game index is the apworld sleight number (item ID minus 2682000) plus 3, which matches
`set_sleights_obtained` starting at journal `+0x1`. Picking up Gravity marking `GRAVIRA` (`0x11`) and `GRAVIGA`
(`0x18`), and the popups for `SLIDING_DASH` and `CROSS_SLASH_PLUS` (`0x43`), confirmed it in game on Steam.
Cross-slash+ is `CROSS_SLASH_PLUS` and Surprise! is `SURPRISE_LV2`/`SURPRISE_LV3`. Indices `0x5A`-`0x5C` (which the
game's obtain function also accepts for Sora) and Riku's sleights (`0x5F`-`0x6B`, `0x6D`) are not named yet.

### Floor rooms
| Function | Arguments | Returns | Description |
| :------- | :-------- | :------ | :---------- |
| `is_outside_floor` | none | boolean | True while a floor is loaded but you are not in any of its rooms (current room ID 0), for example in the Exit Hall after leaving the floor. |
| `is_floor_started` | none | boolean | True once the floor's Start room has been visited (its state record byte `+5` is 1), which happens when the floor's opening event plays. A floor that was just built for a new world is not started yet. |

Each room has a 0x98-byte entry in the room list (`floorRoomEntries`, count in `floorRoomCount`): four doors at
`+0x08` (0x20 bytes each: door type, destination room ID, pointer to the door's state byte), the floor layout record
at `+0x80`, and the room's state record at `+0x88`, whose first word is the world (`0xFFFF` while the room is not
made). Door state bytes are 0 for no door, 1 closed, 2 open.

### Data tables
The game keeps its data files in memory after loading them, and reads most tables straight from there. These
functions change those tables in memory, with no hooks and no file replacement. A setter only records the change; call
`update_data_tables()` every frame and it writes every recorded change into the loaded files, and writes it again if
the game reloads a file. Values that already match are not written. List lengths never change: a shorter list is
padded with weight 0 entries, and a longer one is refused (logged once).

| Function | Arguments | Returns | Description |
| :------- | :-------- | :------ | :---------- |
| `update_data_tables` | none | nothing | Writes every recorded change below into the loaded files. Call it every frame. |
| `list_loaded_files` | `pool` (default 1) | list of `{name, data}` | Every file in one of the game's loaded file pools. Pool 1 holds the data tables, pool 23 the outer `.BIN` archives. `data` is 0 for released files. |
| `find_loaded_file` | `name, pool` (default 1) | address or nil | Data address of a loaded file, by its full name (`"BattleCardList.bin"`, case does not matter). |
| `get_card_stats` | `card_id` | `{powers, cp}` or nil | Reads a card's 4 power values (percent of attack per hit) and base CP from `BattleCardList.bin`. |
| `set_card_cp` | `card_id, cp` | boolean | Sets a card's base CP (0-255). The game's CP for value n is `base + (base / 10) * (n - 1)`, a 0 counts as 10; premium and enemy cards cost the base. |
| `set_card_power` | `card_id, hit, power` | boolean | Sets one of a card's 4 power values (hit 1-4, 0-65535). |
| `get_sleight_stats` | `sleight_id` | `{powers}` or nil | Reads a sleight's 4 power values from `StockSkillList.bin`. IDs match `SLEIGHTS`. |
| `set_sleight_power` | `sleight_id, hit, power` | boolean | Sets one of a sleight's 4 power values. Damage is `power * attack / 100`. |
| `get_story_door_requirement` | `floor_number, door_number` | `{key_index, stages}` or nil | Reads what one story door needs on Sora's floors 1-15, from `RCNorma1.BIN`. `door_number` is one of `STORY_DOORS`. |
| `set_story_door_requirement` | `floor_number, door_number, stages` | boolean | Sets the card stages a story door wants before its key card: a list of at most 3 `{value, kind, colour}` (kinds `STORY_DOOR_KINDS`, colours `STORY_DOOR_COLOURS`). An empty list means the key card alone opens it. Takes effect the next time the floor is built. |
| `set_story_doors_key_only` | none | nothing | Every story door on every floor needs only its key card. A floor's own `set_story_door_requirement` still wins. |
| `set_world_drops` | `world_id, drops` | boolean | Sets one world's drop tables (world 1-13). `drops` can hold `chest_cards` and `object_cards` (lists of `{card, weight}` for chests and breakable objects), `map_cards` (list of `{card, weight}`, map cards 0xA1-0xB8), `random_joker_rate`, `key_to_rewards_rate`, and `map_card_value_weights` (10 weights for values 0-9). Any field left out keeps the game's data. |
| `set_chest_card_value_weights` | `weights` | boolean | Sets the 10 value weights (values 0-9) chests and objects use for battle cards, for every world (`GimCom.bin`). |
| `set_object_card_chance` | `chance` | boolean | Sets the percent chance (0-100) that a breakable object drops a battle card instead of orbs, for every object in every world (`GimProb.bin`). Each room still caps how many cards its objects can give, see `set_object_card_room_cap`. |
| `set_object_card_room_cap` | `cap` | boolean | Sets how many battle cards the breakable objects in one room can give (0-99), for every world (`GimCom.bin`). Once a room reaches it, objects there only drop orbs. |
| `set_drops_ignore_unlocks` | `ignore_unlocks` | boolean | `true` lets chests and breakable objects drop every card in their world's list, even cards the player has never received. `false` puts the game's unlock check back. |
| `set_heartless_reward` | `heartless_card, reward_card` | boolean | Changes the card a Heartless drops at the end of a battle. `heartless_card` is its own enemy card (0x44-0x62, not Darkball), `reward_card` any battle or enemy card Sora can hold. Battle cards get a random value 0-9, changed by `set_heartless_card_value_weights`. |
| `set_heartless_first_drop_guaranteed` | `guaranteed` | boolean | `true` makes each Heartless always drop its card until the player has picked one up from it; after that its normal chance is back. |
| `set_heartless_card_value_weights` | `weights` | boolean | 10 weights (0-100, for values 0-9, at least one above 0) for the value of a battle card dropped by a Heartless. Only used while a Heartless reward or the first drop guarantee is set. Not tested in game yet. |
| `has_first_drop` | `heartless_card` | boolean | Whether this save already has the first drop from that Heartless. |
| `set_first_drop` | `heartless_card, received` | boolean | Sets or clears that. |
| `set_world_card_odds` | `world_id, odds` | boolean | Sets the real percent chance of each card in one world (1-13). `odds` can hold `chest_cards` and `object_cards` (given together, up to 44 `{card, weight}` each, cards 0x01-0x30) and `map_cards` (up to 24, 0xA1-0xB9; 0xB9 is Random Joker) with `random_joker_rate` and `key_to_rewards_rate`. Each list adds up to 100 and can be any length, so it can hold cards the world never drops. Use with `set_drops_ignore_unlocks(true)`. `nil` puts the world back. Wins over `set_world_drops`. |
| `get_drops_ignore_unlocks` | none | boolean or nil | Reads the current state straight from the exe code. |
| `set_moogle_pack_price` | `category, tier, price` | boolean | Sets one Moogle shop pack's price (category from `MOOGLE_CATEGORIES`, tier 0-3). |
| `set_moogle_value_weights` | `tier, weights` | boolean | Sets the 10 card value weights for packs of one tier (0-3). |
| `set_moogle_floor_offer` | `floor_group, packs_per_tier` | boolean | Sets how many packs of tier 0-3 the shop offers in each category on a group of floors (`MOOGLE_FLOOR_GROUPS`). |
| `set_moogle_pool` | `category, entries` | boolean | Sets the cards an attack, magic or item pack can contain: a list of `{card, weights}` with one weight per tier. The shop only picks cards already found in the journal. |
| `set_moogle_fallback_card` | `category, card` | boolean | Sets the card a pack gives when nothing in that category's pool can be picked (every card has weight 0 or is not found in the journal). Category 1 attack (game: Kingdom Key), 2 magic (Cure), 3 item (Potion); card is a battle card id 0x01-0x43. These cards are written in the exe's code, are never premium, and skip the journal check. |
| `set_starting_deck` | `cards` | boolean | The 13 cards Sora starts a new game with: a list of `{card, value}` (battle or enemy cards, values 0-9). Written into the loaded `CardInit.BIN`, so set it before starting the game. Sora starts with 275 CP. Not tested in game yet. |
| `set_boss_fight` | `world_id, arena_room_code, kind, variant, position` | boolean | Puts another boss in a boss arena (world 0 is the Exit Hall), alone in one wave. `position` is an optional `{x, y, z}` to start it from. `variant` is the version of the boss, for example 3 for Riku IV; it also picks the boss reward record. Not tested in game yet. |
| `set_enemy_kind_multipliers` | `kind, {hp, attack, exp}` | boolean | Multipliers for one enemy kind, on top of the ones for every enemy. |
| `set_moogle_any_card` | `allowed` | boolean | `true` lets the Moogle shop sell cards that are not found in the journal yet. Not tested in game yet. |
| `set_world_order` | `worlds` | boolean | Fixes the world of every floor in Sora's story: a list of 13 world IDs, floor 1 first. Each world once, and floor 13 must be Castle Oblivion. The world select then offers one world per floor. Back to normal in Riku's story. Set it before the game is started; floors already chosen do not change. |
| `set_floor_layout_order` | `layouts` | boolean | Which of the game's layouts (1-12, the floor it normally belongs to) each of floors 1-12 uses. Twilight Town needs layout 11 and Destiny Islands layout 12; Traverse Town to Hollow Bastion need one of 1-10. The Exit Hall scenes stay with the floor. Call it before the other layout functions, which use the new floor numbers. |
| `set_floor_size` | `floor_id, width, depth` | boolean | Sets the map size (1-7 rooms each way) of a floor from 1 to 12. |
| `get_floor_layout` | `floor_id` | `{floor_id, rooms}` or nil | Reads one of Sora's floor layouts from `Rooms1.BIN`. `floor_id` is 1-15, or 100 for 100 Acre Wood. `rooms[room_id]` is `{id, type, fix_scene, x, y, doors}`; `doors[1-4]` is `{destination, type, check_event}` (destination 0 = no door). |
| `set_floor_room` | `floor_id, room_id, room` | boolean | Changes one room of a floor layout. `room` can hold `type` (`FLOOR_ROOM_TYPES`), `fix_scene` (the room code Extra, Last and Fix rooms get), `x` and `y`; fields left out keep the game's data. Takes effect the next time the floor is built. |
| `set_floor_door` | `floor_id, room_id, door_number, door` | boolean | Changes one door (1-4) of a room. `door` can hold `destination` (a room id on the same floor, 0 = no door), `type` (`FLOOR_DOOR_TYPES`) and `check_event`; fields left out keep the game's data. Door 1 leads to y + 1, door 2 to x + 1, door 3 to y - 1, door 4 to x - 1. A door does not open from the other side unless that room's door points back. Takes effect the next time the floor is built. |
| `set_event_card_reward` | `world_id, room_code, original_card, new_card, new_value` | boolean | Changes a card an event script gives with its popup (story rewards such as Simba from Leon's tutorial, world 1 room code 2003, card `0x23`, or a floor's Key of Beginnings). `world_id` 0-13 and `room_code` 0-9999 name the room's script `WOwwrrrr.ABC`; every give of `original_card` in that script becomes `new_card` (card ID 0x01-0xCA) with `new_value` (0-9). Takes effect when that room's script loads. It also changes the cards two fights drop: Agrabah world 2, room 2003, card `0x2D` (Ether) and Monstro world 5, room 1051, card `0x26` (Dumbo). Those two are not tested in game yet. |
| `set_event_sleight_reward` | `world_id, room_code, original_sleight, new_sleight` | boolean | Same for a sleight an event script gives (sleight index, see `SLEIGHTS`). |
| `set_card_sleight` | `card_id, sleight_number, sleight_id` | boolean | Changes one of the two sleights (1 or 2) that come with the first copy of a magic (0x1A-0x20) or summon (0x23-0x29) card. Exe code `cardSleightCode`, Steam `0x15C89B`, EGS `0x15C50B`. Not tested in game yet. |
| `set_room_of_rewards_reward` | `world_id, chest_number, reward` | boolean | Changes what a Room of Rewards (Key to Rewards room) chest gives. `chest_number` 1 is the first chest, 2 the one that needs 358/2 Days watched. `reward` is `{card = id}` or `{sleight = id}`; `nil` puts the game's reward back. A chest that gives a sleight can only give a sleight; a card chest can give either. Card values are still rolled from the chest value weights. 100 Acre Wood has none. |
| `set_bounty_reward` | `world_id, chest_number, reward` | boolean | Same for the bounty chests: the first chests opened in each world (chest 1; Atlantica, Twilight Town and Destiny Islands have a chest 2, Castle Oblivion 2 and 3, which need the game cleared). |
| `set_bounties_ignore_clear` | `ignore` | boolean | `true` gives the four bounties that need the game cleared (Twilight Town 2, Destiny Islands 2, Castle Oblivion 2 and 3) right away. The save is not changed. Not tested in game yet. |
| `get_room_of_rewards_reward` / `get_bounty_reward` | `world_id, chest_number` | `{card}` or `{sleight}` or nil | Reads what the chest gives now, straight from the exe code. |
| `get_room_of_rewards_chests` / `get_bounty_chests` | none | list of `{world, chest, kind, vanilla}` | Every chest the two functions above can change, with its vanilla reward. |
| `get_world_enemy_kinds` | `world_id, arena_room_code` | list of kinds or nil | The enemy kinds a world loads for one battle arena (room code 1000-1999, for example 1001), in load order, from the exe's room manifest. A kind is the `ENEMY/00kk` folder number (1 Shadow, 4 Blue Rhapsody, 9 Large Body, 18 Sea Neon). |
| `set_world_enemy_kinds` | `world_id, arena_room_code, kinds` | boolean | Changes the enemy kinds a world loads for an arena, in order. The list can not be longer than the arena's own list (Olympus arena 1001 has 6); slots after it keep the game's kinds. Any kind some world loads can be used, so enemies from other worlds work. Must be in place before the world's arena loads (entering the floor or loading a save). |
| `set_world_enemy_swaps` | `world_id, swaps` | boolean | Replaces enemy kinds in a whole world, on the field and in battles: a list of `{from, to}` (kinds 1-36, each used once). Worlds 1-9 and 11-13. Scripted fights and bosses are not changed. Takes effect when the world's rooms are loaded next. |
| `get_battle_formation` | `world_id, arena_room_code, formation` | list of waves or nil | Reads one battle formation (0-31) from the loaded arena file `WOwwrrrr.ESD`: a list of waves, each a list of enemy kinds. Nil while that arena file is not loaded. |
| `set_battle_formation` | `world_id, arena_room_code, formation, kinds` | boolean | Changes the enemy kinds of one battle formation (0-31). The formation keeps its number of enemies and waves; enemy n gets `kinds[n]`, starting over from the first kind when the list runs out. A kind must also be loaded by that world (`set_world_enemy_kinds`) or the battle will crash. Written as soon as the arena file is loaded; battles read it when they start. |
| `set_enemy_deck` | `kind, counts` | boolean | Sets an enemy kind's deck: 10 numbers, how many cards of each value 0-9 it holds (0-20 each, at least one card). Shadow (1) holds one value-1 card, so `{0, 0, 0, 0, 0, 0, 0, 0, 0, 1}` gives every Shadow a 9 instead. Kinds without a deck (White Mushroom) are refused and logged. |
| `set_enemy_hp_multiplier` | `multiplier` | boolean | Multiplies every enemy's HP on every floor (0-100, rounded, at least 1). |
| `set_enemy_attack_multiplier` | `multiplier` | boolean | Multiplies every enemy's attack power on every floor (0-100, rounded). |
| `set_enemy_exp_multiplier` | `multiplier` | boolean | Multiplies the EXP every enemy gives on every floor (0-100, rounded). |

| Table | Values |
| :---- | :----- |
| `STORY_DOORS` | `KEY_OF_BEGINNINGS` 1, `KEY_OF_GUIDANCE` 2, `KEY_TO_TRUTH` 3, `KEY_TO_REWARDS` 4 |
| `STORY_DOOR_KINDS` | `ANY_VALUE` 0, `AT_MOST` 1, `AT_LEAST` 2, `EQUAL` 3, `TOTAL` 4 (card values add up to `value`) |
| `STORY_DOOR_COLOURS` | `ANY` 0, `RED` 1, `GREEN` 2, `BLUE` 3 |
| `MOOGLE_CATEGORIES` | `ATTACK` 1, `MAGIC` 2, `ITEM` 3, `MIXED` 4 |
| `MOOGLE_FLOOR_GROUPS` | `FLOOR_1` 1, `FLOORS_2_TO_6` 2, `FLOORS_7_TO_10` 3, `FLOORS_11_AND_UP` 4 |
| `FLOOR_ROOM_TYPES` | `CARD` 0, `START` 1, `EVENT_1` 2, `EVENT_2` 3, `EVENT_3` 4, `GOAL` 5, `EXTRA` 6, `LAST` 7, `FIX` 8 |
| `FLOOR_DOOR_TYPES` | `NORMAL` 0, `TO_EVENT_1` 1, `TO_EVENT_2` 2, `TO_EVENT_3` 3, `OPEN_AFTER_EVENT` 4, `TO_GOAL` 5, `TO_EXTRA` 6, `ONE_WAY` 7, `WORLD_ENTRANCE` 8, `SELECT_WORLD` 9, `FLOOR_CHANGE` 10, `TO_LAST` 11, `EVENT_ROOM` 12, `DEBUG` 13 |

How it finds the files: the game keeps a list of loaded files per pool (`loadedFilePoolTable`, Steam `0xAC6730`, EGS
`0xAC6130`). Each node has the file entry at `+0x08` and the next node at `+0x10`; the entry has a file object at
`+0x08` and the name at `+0x10`; the file object has the data pointer at `+0x08`.

Notes:
- Chest and object weights are picked with `rand % 100`, so a world's weights should add up to 100. A chest that lands
  on a card the player has not unlocked yet rolls again among that world's basic cards, unless
  `set_drops_ignore_unlocks(true)` is on.
- Heartless drops: the last enemy defeated in a battle rolls its drop chance (`@ENP + 0x10` in `EN00kk.epd`, percent) for
  the card in `heartlessCardTable` (one u32 per enemy kind). That table also sets the card the Heartless attacks with, so
  27 bytes at `heartlessSetupCode` are changed to read the attack card and the drop card from separate bytes of the entry.
  50 bytes at `heartlessDropCode` are rewritten to give a random value and to write the enemy kind to
  `heartlessDropSignal` (spare memory). When the reward's count goes up after that, bit 0x80 of a journal byte
  (journal `+0x7B` on) marks the first drop, so it is saved with the game. The game's own conditions stay: no drop in the
  tutorial, with 4 or fewer map cards, or when the card can not be held. Not tested in game yet.
- Card odds: `set_world_card_odds` writes its own lists into spare memory at the end of the exe's `.text` section
  (`cardOddsBuffer`, 464 bytes) and changes 9 bytes in the two functions that read `AtkCardDrop.bin` and
  `MapCardDrop.bin` (`battleCardListReadCode`, `mapCardListReadCode`) so they read those lists. The game normally rolls
  a world's special cards first and its 12 standard cards second; `standardDropCardTable` is the byte table that says
  which are standard, and it is set so everything is in the first roll. Both go back to normal in worlds without odds.
  New odds show from the next room on. Not tested in game yet.
- Drop unlocks: the check is an exe function (`dropUnlockCheckCode`, Steam `0x1C04D0`, EGS `0x1C0080`) that allows any
  card above 0x30 without looking at the save. `set_drops_ignore_unlocks` changes that limit (the byte at `+0x0D`) to 0,
  so every card is allowed. Only the chest and object rolls use it, and nothing in the save changes. Not tested in game yet.
- The drop manager (the object that rolls chest, object and map card drops) copies the drop lists out of the files
  every time a room is set up, so drop changes show from the next room on, not in the room you are standing in.
  Which world's file is loaded is read from the `WO02xx.BIN` archive in pool 23.
- The Moogle shop files are only loaded while a shop is open. The changes are written as soon as they appear.
- World order: the world select code has a path that offers one world per floor (normally floors 11-13). Two jumps
  (`worldSelectFirstJump`, `worldSelectSecondJump`) are changed so floors 2-13 all use it; it reads 12 u16 world IDs from
  `worldSelectOneWorldTable` (Steam `0x51D584`, EGS `0x51D694`), which overlap the other world select tables. Floor 1 is
  an immediate at `worldSelectFirstFloorCode`. Do not use it together with `set_world_select_card`. Not tested in game yet.
- Floor layouts can not grow: each floor keeps its room count, and every room keeps 4 door slots. The game builds a floor's room list from `Rooms1.BIN` (`fnc_build_floor_rooms`) when the floor is built (for example after picking its world card), so layout changes show on floors built after the write, not on a floor that is already built.
- Event rewards: the room's event script is loaded by name into file pool 37 (`WO010006.ABC` for world 1 room 6). A give is the instructions push 5 (card with popup) or push 7 (sleight), push the card ID, push the value, then opcode `0xAD`; each instruction is 8 bytes (`u16 opcode, u16 flag, s32 operand`, `0x1C` = push). The game copies a script's code into its own buffer once the file is loaded, a frame or more later, so the change has to be in the file before that; `update_data_tables()` writes it as soon as the file appears. Tested in game on Steam: a floor's opening event gave Crabclaw instead of the Key of Beginnings.
- Enemies: a field battle picks one of the arena file's 32 formations: the room's map card sets a range (normal rooms 0-6, White Room 13-15, Black Room 16-18, Bottomless Darkness 19-23) and the game prefers formations that contain the kind of field enemy you touched. The kinds a world loads come from the exe's resource manifests (`resourceManifestTable`, one per category; `[100 + world]` lists each room's files, and an arena lists its enemies as resource numbers `"1200kk"`); `set_world_enemy_kinds` points those entries at another kind's string. Loaded arena files store their offsets as handles (`0x80000000 | segment << 25 | low 25 bits`, segment bases at `handleSegmentTable`). Tested in game on Steam: Sea Neons in Olympus Coliseum.
- Room of Rewards and bounty chests: the rewards are immediates in two exe functions, the Room of Rewards chests (room code 0x18, `roomOfRewardsChestCode`, Steam `0x1BD9D0`, EGS `0x1BD580`) and the first chests of each world (`bountyChestCode`, Steam `0x1BE4E0`, EGS `0x1BE090`). Each reward is `mov dword [rdi], sleight` (6 bytes) or `mov dword [rdi+4], card` (7 bytes); a card chest becomes a sleight chest by changing the displacement 4 to 0. The code is checked before every write. Several sleight chests only give their sleight when script byte 0x61 is not 3, and otherwise roll a normal card. Not tested in game yet.
- Enemy stats: each enemy kind's `ENEMY/00kk/EN00kk.EPD` stays loaded while its world is (file pool 21, `EN00kk.epd`, starting at `@ENP`). `@ENP + 0xB0` is 13 rows of `{s32 HP, s32 attack, s32 EXP, 0}`, one per floor; `@ENP + 0x184` is the deck, one count per card value 0-9 (`@ENP + 0x44` is 0 for kinds without one). Battles read the loaded copy, so changes apply from the next battle. Tested in game on Steam (Sea Neon HP 1, EXP 999, one value-9 card).

### World select tables
When Sora (or Riku) starts a floor, the world-select screen builds its list of world cards from three tables in
the exe (EGS `0x12EE00`, the code that sets up `wselect.lad`). `floor_group` picks the table and `story` is
`"sora"` or `"riku"`.

| `floor_group` | Floors | Slots | Sora (vanilla) | Riku (vanilla) | How the screen uses it |
| :------------ | :----- | :---- | :------------- | :------------- | :--------------------- |
| *(hardcoded)* | 1F | - | Traverse Town | Hollow Bastion | Only world offered on the first floor. Not in a table. |
| `floors_2_to_6` | 2F-6F | 5 | Agrabah, Olympus Coliseum, Wonderland, Monstro, Halloween Town | Agrabah, Monstro, Neverland, Traverse Town (5th slot `0x270F`, unused) | Offers every slot not already used on floors 2-6 (Riku: 2-5). Sora reads 5 slots, Riku 4. |
| `floors_7_to_10` | 7F-10F | 4 | Atlantica, Neverland, Hollow Bastion, 100 Acre Wood | Atlantica, Olympus Coliseum, Wonderland, Halloween Town | Offers every slot not already used on floors 7-10 (Riku: 6-9). |
| `floors_11_to_13` | 11F-13F | 3 | Twilight Town, Destiny Islands, Castle Oblivion | Destiny Islands, Twilight Town, Castle Oblivion | One world per floor, in slot order. Only the low byte is read. |

A world is skipped if an earlier floor in the same group already uses it. The screen does not check whether the
player owns the world card, so these tables alone decide what is offered.

World IDs are in `WORLDS`:

| Table | Values |
| :---- | :----- |
| `WORLDS` | `TRAVERSE_TOWN` 1, `AGRABAH` 2, `OLYMPUS_COLISEUM` 3, `WONDERLAND` 4, `MONSTRO` 5, `HALLOWEEN_TOWN` 6, `ATLANTICA` 7, `NEVERLAND` 8, `HOLLOW_BASTION` 9, `HUNDRED_ACRE_WOOD` 10, `TWILIGHT_TOWN` 11, `DESTINY_ISLANDS` 12, `CASTLE_OBLIVION` 13 |
