# KHRECOM Lua Library

A shared Lua library of helper functions for reading and writing Kingdom Hearts Re:Chain of Memories (PC)
memory, for use in the [Archipelago integration](https://github.com/gaithern/KH-RECOM-AP-LUA) and other
[LuaBackend](https://github.com/Sirius902/LuaBackend) mods. Supports both the Steam and EGS builds.
Modeled on [KH1-LUA-LIBRARY](https://github.com/gaithern/KH1-LUA-LIBRARY).

## Repository Layout

- `dll/*`

  | File | Description |
  | :--- | :---------- |
  | `lua54.dll` | Bundled Lua 5.4 module that `cffi.dll` links against. Panacea loads it automatically. Same file as KH1-LUA-LIBRARY's. |

- `scripts/io_packages/*`

  | File | Description |
  | :--- | :---------- |
  | `VersionCheck.lua` | Detects the EGS or Steam build, then loads that build's address file and `memory_locations.lua`. Sets `canExecute` and `gameVersionName`. |
  | `EGSGlobal.lua` | Addresses (RVAs) for the Epic Games Store build. |
  | `SteamGlobal.lua` | Addresses (RVAs) for the Steam build. |
  | `memory_locations.lua` | Named offsets from the base pointers in the version files, plus table sizes. Shared by both builds. |
  | `khrecom_lua_library.lua` | Main script to be used by outside mods. Contains callers for all functionality. |
  | `helpers/bits.lua` | Bit and list helpers. |
  | `helpers/native.lua` | Calls game functions and allocates native memory through cffi. See [Calling game code](#calling-game-code). |
  | `helpers/call_redirect.lua` | Points one `call` (or tail-call `jmp`) instruction in the game at a Lua function. |
  | `modules/cards.lua` | Battle card inventory slots and deck byte layout. |
  | `modules/exe_tables.lua` | Static tables inside the game exe: level-up sleights, boss rewards, world select offers, EXP gems. |
  | `modules/world_select.lua` | Hook on the world-select screen setup, so a script can choose exactly which worlds a floor offers. |
  | `modules/floor_warp.lua` | Hook on the World Warp menu, so floors without a world can still be warped to. |
  | `modules/item_popup.lua` | Shows the game's "obtained" popup for any card or sleight, without giving it. |
  | `modules/card_ids.lua` | Named IDs for every card, grouped by card type. |
  | `modules/sleight_ids.lua` | Named game indices for every sleight Sora can get. |
  | `modules/story_rewards.lua` | Hooks on boss rewards, battle pickups and event script rewards, so a script can see or replace them. |
  | `cffi.dll` | [cffi-lua](https://github.com/q66/cffi-lua), a C FFI for Lua, built against `dll/lua54.dll` by `build_cffi.py`. MIT, see `cffi_LICENSE.txt`. Same build as KH1-LUA-LIBRARY's. |
  | `json.lua` | Generic lua helper. From [RXI's json.lua](https://github.com/rxi/json.lua). |
- `build.py`
  - Creates `mod.yml` by calling `generate_mod_yml.py`. With `--cffi`, rebuilds `cffi.dll` first.
- `build_cffi.py`
  - Rebuilds `cffi.dll` from a pinned cffi-lua commit with MSYS2's UCRT64 toolchain. Only needed when changing the cffi-lua version, since the built dll is committed.
- `generate_mod_yml.py`
  - Generates `mod.yml` from the files under `scripts/` and `dll/`.
- `mod.yml`
  - OpenKH configuration file listing the files to ship.

## Building mod/making changes
After changing scripts, run `python build.py` to regenerate `mod.yml`.

## Calling game code
Everything that runs game code is Lua, using [cffi-lua](https://github.com/q66/cffi-lua) (`require("cffi")`).

- **Calling a game function**: `helpers/native.lua`'s `call_function(rva, ...)` casts `BASE_ADDR + rva` to a
  function taking that many `uint64_t` arguments and calls it. It returns `true, result`.
- **Letting the game call Lua**: `cffi.cast("<function type>", lua_function)` makes a native function pointer that
  runs the Lua function. `helpers/call_redirect.lua`'s `redirect_call(call_site, expected_target, function_type, lua_function)`
  points one `call` or tail-call `jmp` at it through a small jump stub placed near the game code. The original
  target is left untouched, so the Lua function can still call it. The redirect is undone when the Lua state closes.
- **Memory that outlives a script**: `persistent_block(key, size)` returns the same zeroed block to every script and
  after every reload, for the life of the game process. The 8-byte slot holding its address is a named file
  mapping view (`Local\khrecom_lua_library_<pid>_<key>`).

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
| World select hook (`worldSelectSetup*`, `getCurrentFloorIndexFunction`, `isSoraStoryFunction`) | both | Tested in game on Steam: replacing the list works. An empty list crashes the game, so locked floors show their card with confirm locked instead. The confirm lock, card and logo dimming, and the "(Locked)" name all work in game on Steam; EGS is untested. |
| Floor warp hook (`floorWarpBuild*`) | EGS | Tested in game on Steam. The EGS addresses were found by matching the Steam code bytes. |
| Sleight popup (`gameAllocateFunction`, `getTaskParentFunction`, `sleightPopupConstructor`) | EGS | Tested in game on Steam. The EGS addresses were found by matching the Steam call sites. |
| Story reward hooks (`giveItem*`, `giveSleightFunction`, `eventGive*`, `bossRewardGiveJumpSite`, `battlePickupGiveJumpSite`) | EGS | Boss reward and battle pickup tested in game on Steam; the event script hooks install but have not fired yet. The EGS addresses were found by matching the Steam call sites. |
| Custom popup text (`getItemNameFunction`, `popupItemNameCallSite*`, `popupQueuedItemNameCallSite`) | EGS | Tested in game on Steam. The EGS addresses were found by matching the Steam call sites. |
| Item popup (`showItemPopupFunction`, `itemTable`) | EGS | Tested in game on Steam. The EGS addresses were found by matching the Steam code bytes. |
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

### World select hook
| Function | Arguments | Returns | Description |
| :------- | :-------- | :------ | :---------- |
| `set_world_select_handler` | `handler` | boolean | Hooks the world-select screen setup (both call sites). After the game builds its own list, `handler(floor_number, is_sora_story, vanilla_choices)` is called; `floor_number` is 1-13. Return a list of world IDs (1 to 5) to replace the offer, or `nil` to keep the game's list. Return `true` as a second value to lock the offer: the card is shown dimmed and confirm does nothing. Returns false if the hook could not be installed. |
| `get_world_select_choices` | `world_select` | list of bytes | Reads the offer list from a world-select object (`+0xE0` count, `+0xEC` world IDs). |

The hook redirects the calls at EGS `0x1E7F4B`/`0x1E9E84` (Steam `0x1E833B`/`0x1EA274`) to the setup function
(EGS `0x12EE00`, Steam `0x12F190`). The Lua callback runs the original setup, asks the game for the current floor
(EGS `0x233330`, Steam `0x2337C0`) and story (EGS `0x1AA770`, Steam `0x1AAB00`), then rewrites the list. A handler
error is caught and written to `khrecom_lua_library.log` so the game keeps its own list.

An empty list can't be used: the screen builds one card object per choice and later calls methods on card 0
and on the selected card without checking the count, so the game crashes. `{}` is refused (the game keeps its own
list) and the refusal is logged. To lock a floor, offer its world and return `true` as a second value
(`return {world_id}, true`). Installing the handler also redirects the confirm-button check (call at EGS
`0x1303FF`, Steam `0x13078F`, to EGS `0x1118A0`, Steam `0x111C30`, which takes the world select object and returns
whether confirm was pressed) to Lua, which returns 0 ("not pressed") while the floor is locked. The card is shown
and the player can cancel out, but can't enter the world. The lock is cleared every time the screen is set up.

A locked card is also dimmed. Each card is a layout object (node at `+0x10`). The sprite draw code (Steam
`0x24BB10`) multiplies every sprite's color by its node's color at node `+0x110` (object `+0x120`, RGBA floats), but
only while the node's byte at node `+0x128` (object `+0x138`) is set; the result is passed down to child nodes.
Every frame the screen sets each card's size with `(y + 75) * 0.35 / 150 + 0.65` (back cards are smaller) through a
scale setter (EGS `0x248290`, Steam `0x2486E0`, arguments: layout object, float scale). That call (EGS `0x130A68`,
Steam `0x130DF8`) is redirected to Lua, which calls the original and then, while locked, writes RGB 0.35 and alpha 1
to every card object (pointers at world select `+0x118`) and sets their color switch. It also darkens the world logo,
a separate layout object at world select `+0x170`, to RGB 0.15 so it is barely visible (alpha stays 1); that
pointer is null while the screen is opening or closing, so it is checked first. The world select object comes from
the setup hook.

The world name in the name box is drawn every frame from a string pointer at `+0x58` of a text object at world
select `+0x188` (vtable Steam `0x606C98`). While locked, the same Lua callback reads the game's name string, writes
it plus " (Locked)" into a 64-byte `persistent_block`, and points `+0x58` at the block (only when it doesn't already
point there). The longest name, "Olympus Coliseum (Locked)", was tested live and fits in the box.
World select `+0x168` is the name box frame. All of this is tested in game on Steam.

### Card IDs
One ID numbers every card in the game. The same number is the item ID the popup and give functions take, the
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
| `PLACEHOLDER_CARD` | `0x3A` | Not a table: Guard Armor's gimmick card, which only says "Gimmick". `show_custom_popup` without an `item_id` cycles through all 8 gimmick cards starting here. |

`BUMBLE_RUMBLE_CARDS`, `GIMMICK_CARDS`, `BOSS_ATTACK_CARDS` and `SPECIAL_CARDS` have no English name in the item
table ("-", the boss's name, or an internal Japanese name); they were identified by showing each one with
`show_custom_popup` in game on Steam. `0x81`-`0x9E` are left out: their internal Japanese names are boss names with
letters (Cloud A-B, Hades A-B, Hook A-D, Axel A-B, Larxene A-C, Riku A-D, Vexen A-B, Marluxia A-C, 2 and 3,
Lexaeus A-C, Ansem A-B, Zexion A), probably cards bosses use in battle, and the popup has no picture for them: it
shows a plain Keyblade card with a red frame (type `0x17`) or a blue one (type `0x27`). Every other ID from `0x01` to
`0xCA` shows a real card, so there is no blank card to use as a placeholder.

### Story rewards
| Function | Arguments | Returns | Description |
| :------- | :-------- | :------ | :---------- |
| `set_story_reward_handler` | `handler` | boolean | Hooks the places the game hands out rewards. Each time one runs, `handler(kind, id, value)` is called; return `true` to skip the game's own reward, anything else to let it happen. `kind` is one of `REWARD_KINDS` below. A handler error is logged and the reward goes through. `nil` removes the handler (the hooks stay but do nothing). Returns false if a hook could not be installed. |

| `REWARD_KINDS` | Hooked call (Steam / EGS) | What it is | `id`, `value` |
| :------------- | :------------------------ | :--------- | :------------ |
| `BOSS_REWARD` (`"boss_reward"`) | jump at `0x187B37` / `0x1877A7` | The card a boss gives when beaten. `0x187AA0` finds the boss in `bossRewardTable` (25 entries of `0x18` bytes) and gives that entry's card with a popup | card ID, value |
| `BATTLE_PICKUP` (`"battle_pickup"`) | jump at `0x230FB3` / `0x230B23` | Things picked up in battle (`0x230F90`, item at object `+0x244`, value at `+0x248`): friend cards, gimmick cards, and IDs `0xCC`-`0xD1` with amounts (orbs, not cards) | ID, value or amount |
| `ITEM_WITH_POPUP` (`"item_with_popup"`) | call at `0x146006` / `0x145C76` | Event script command: give a card and show its popup | card ID, value |
| `ITEM` (`"item"`) | call at `0x1468D0` / `0x146540` | Event script command: give a card without a popup | card ID, value |
| `SLEIGHT` (`"sleight"`) | call at `0x146065` / `0x145CD5` | Event script command: give a sleight (then the full-screen popup when its show flag is set) | sleight index, `nil` |

All of these end in the same functions: give with popup EGS `0x1F46C0`, Steam `0x1F4AB0(item_id, value, mode)`; give
EGS `0x158C30`, Steam `0x158FC0(item_id, value)`; mark sleight EGS `0x23A610`, Steam `0x23AA60(sleight_index)`. The
boss reward and battle pickup code reach the first one with a tail jump, not a call. Field card pickups
(Steam `0x1C982F` and a copy at `0x433420`) are not hooked. On Steam, beating Guard Armor logged `battle_pickup` for
his gimmick card (`0x3A`), Donald's friend card (`0x31`) and orbs (`0xD0`, value 24), then `boss_reward` for his
enemy card (`0x63`). The event script commands have not fired yet in testing (Exit Hall bosses give their card
through the boss reward), and where Exit Hall sleights such as Aerora come from is not known yet.

### Sleight IDs
`SLEIGHTS` names every sleight Sora can get, using the game's sleight index (the number `show_sleight_popup` and the
journal sleight functions take), for example `khrecom.SLEIGHTS.SLIDING_DASH` (`0x04`) to
`khrecom.SLEIGHTS.LUCKY_BOUNTY_LV3` (`0x56`). Sleight names are not in the exe, so the table was generated from the
apworld's `Data/items.csv`: the game index is the apworld sleight number (item ID minus 2682000) plus 3, which matches
`set_sleights_obtained` starting at journal `+0x1`. Picking up Gravity marking `GRAVIRA` (`0x11`) and `GRAVIGA`
(`0x18`), and the popups for `SLIDING_DASH` and `CROSS_SLASH_PLUS` (`0x43`), confirmed it in game on Steam.
Cross-slash+ is `CROSS_SLASH_PLUS` and Surprise! is `SURPRISE_LV2`/`SURPRISE_LV3`. Indices `0x5A`-`0x5C` (which the
game's obtain function also accepts for Sora) and Riku's sleights (`0x5F`-`0x6B`, `0x6D`) are not named yet.

### Item popup
| Function | Arguments | Returns | Description |
| :------- | :-------- | :------ | :---------- |
| `show_custom_popup` | `text, item_id, value, is_premium` | boolean | Shows the small card popup with `item_id`'s card picture and value (`item_id` defaults to `PLACEHOLDER_CARD`, `value` to no number) but `text` (plain ASCII, up to 63 characters) instead of the card's name. Use it for sleights or for items from other games. Only shows the popup. Returns false (and logs why) for text that is not a string or is too long, or for the same card problems as `show_item_popup`. |
| `show_sleight_popup` | `sleight_index` | boolean | Shows the game's sleight popup for one sleight. Only shows the popup: the journal is not changed. Returns false (and logs why) when the index is not a number from `0x00` to `0x6D`. |
| `show_item_popup` | `item_id, value, is_premium` | boolean | Shows the game's "obtained" popup for an item. `value` is the card value 0-9, or `nil` for a card with no number; pass `is_premium` as `true` for a premium card (ignored when `value` is `nil`). Only shows the popup: nothing is added to the inventory. Returns false (and logs why) when the item ID is outside the item table, has no item type, or the value is not 0-9 or `nil`. |

`item_id` is the game's item ID; use the tables in [Card IDs](#card-ids), for example
`show_item_popup(khrecom.MAGIC_CARDS.FIRE, 7)`.

Sleights are not in this table; use `show_sleight_popup` for them.

Each sleight has a 2-bit state in the journal (4 per byte, starting at journal `+0x1`). EGS `0x23A610`, Steam
`0x23AA60(sleight_index)` sets a sleight to 1 if it is still 0; Steam `0x23AF10(sleight_index, state)` writes the
state, and Steam `0x23AFC0(sleight_index)` moves a sleight from 1 to 2 (only debug code calls it directly). Getting a
card marks the sleights that use it: picking up Gravity calls `0x23AA60` for `0x11` and `0x18`.

The event script's "give sleight" command (Steam around `0x14603B`) calls `0x23AA60`, then, when its show flag is
set, builds the popup: it gets `0x2C0` bytes from the game's allocator (EGS `0x4AC984`, Steam `0x4ACE54`), gets the
parent task group with EGS `0x2ACDE0`, Steam `0x2AD300(1)`, and runs the popup constructor (EGS `0x10E630`, Steam
`0x10E9C0(object, parent, sleight_index)`). The constructor registers the popup as a game task, so the game runs and
frees it. `show_sleight_popup` makes the same three calls. Tested in game on Steam with sleight `0x43`. That popup
covers the whole screen, so `show_custom_popup` is usually the better way to show a sleight.

The card popup gets its text from EGS `0x164910`, Steam `0x164CA0(&record)`, which picks a message ID for the item
ID from a table (Steam `0x528560`) and returns that message's text from the game's message files (plain ASCII,
null-terminated). The item table's name pointer is not used. The popup calls it from three places: Steam
`0x20DB95` and `0x20DD3B` (EGS `0x20D705`, `0x20D8AB`) when it opens, and Steam `0x209644` (EGS `0x2091B4`) for the
next queued record (the popup queues up to 4). `show_custom_popup` redirects all three calls to Lua the first time
it is used, writes the text into one of four 64-byte slots in a `persistent_block`, remembers it together with the
4-byte record, and shows the popup. When a lookup's record matches a remembered one, the hook returns that text
(the newest match wins); every other lookup goes to the original. Each text is kept for 10 seconds rather than used
once, because the popup looks the name up again while it fades out (using it once made the real name flash).
Without an `item_id`, `show_custom_popup` cycles through the 8 gimmick cards (`0x3A`-`0x41`, all shown as
"Gimmick") so queued placeholder popups have different records and keep their own text. If the game shows the
exact same card and value within those 10 seconds, its popup takes the custom text. Tested in game on Steam,
including two queued custom popups, a 63-character text (it fits in the box) and a replaced boss reward.

Picking up a card in the field goes through EGS `0x1F46C0`, Steam `0x1F4AB0` `(item_id, value, mode)`. It builds a
4-byte record (u16 item ID, value byte, type byte from the item table's first byte), gives the item with Steam
`0x158FC0(item_id, value)` (the general give function, about 45 callers including the event script command), then
shows the popup with EGS `0x20D4B0`, Steam `0x20D940(&record, kind, 0)`. The popup only displays; it never touches
the inventory. In the value byte, bit `0x10` marks a premium card and the low 4 bits are the value; `0xFF` means no value (the pickup code writes it for some card types at Steam `0x1F4B37`) and shows the card without a number, which was tested in game on Steam with attack, magic, item, gimmick, map and enemy cards. `show_item_popup`
writes the record to a `persistent_block` and calls the popup through `native.call_function`. Normal and premium
magic cards and a world card (Neverland) were tested in game on Steam.

`kind` picks the display: 1 is the small box, 2 the full-screen card. Kind 1 is skipped while game flag `0xE2` is
set (`0x1B08C0(1, 0xE2)`), which is the case right after a battle. `0x1F4AB0` with mode 1 (boss rewards, battle
pickups) uses the player object's `+0x390` plus 1, or 1 when there is no player object (pointer at
`attackPowerPointer`); mode 2 (field pickups, event script) always uses 2. The library uses the mode 1 rule, so its
popups are small in the field and full screen after a boss, like the game's own. Both were checked in game on Steam
(a replaced boss reward came out as kind 2).

### Floor warp hook
| Function | Arguments | Returns | Description |
| :------- | :-------- | :------ | :---------- |
| `allow_warp_to_unassigned_floors` | `handler` (optional) | boolean | Lets the World Warp menu reach every floor, even floors with no world assigned yet. For each of those floors, `handler(floor_number)` is called (`floor_number` is 1-13); return a world ID to show that world's icon and name, or `nil` for a blank card. Without a handler every such floor is blank. Display only: the floor's real world assignment is not changed. Returns false if the hook could not be installed. |

The warp menu builds its floor list each time it opens (EGS `0x131090`, Steam `0x131420`, called only from EGS
`0x131999`, Steam `0x131D29`). It reads each floor's world, and the highest floor you can pick (menu `+0xD4`) is the
floor before the first floor with world 0. Vanilla never has a gap because worlds are assigned as you climb, so a
randomizer that leaves floors unassigned would cap the menu.

The menu keeps two 16-byte tables: `+0x228` is the world ID minus 1 (the name) and `+0x238` is the icon. A floor
with no world gets `0xFF` in both, and drawing that crashes the game. `0x0E` is the game's own blank entry (it uses it
for the current floor when you stand above the last reachable one) and shows an empty card with no name.

The game fills the icon table from the world ID like this: worlds 1-9 use world ID - 1, 100 Acre Wood (`0x0A`) uses
the byte at menu `+0xD8` plus 9, worlds `0x0B`-`0x0D` use the world ID, and anything higher uses 0.

The hook redirects the builder call to Lua, runs the original, and then, for every floor whose world entry is `0xFF`,
asks the handler for a world. If one comes back, it writes that world's entries using the rules above; otherwise it
writes `0x0E` to both tables. It then sets `+0xD4` to 12 (13F). The real world assignments are not changed, so a
floor's world select still decides what the floor holds. Warping to a blank floor and showing unlocked worlds on
unassigned floors were tested in game on Steam; EGS is untested.

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
