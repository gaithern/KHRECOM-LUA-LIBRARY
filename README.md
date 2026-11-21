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
| World select hook (`worldSelectSetup*`, `getCurrentFloorIndexFunction`, `isSoraStoryFunction`) | both | Tested in game on Steam: replacing the list works. An empty list crashes the game, so locked floors show their card with confirm locked instead. The confirm lock works on Steam; dimming is not yet tested in game. |
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
(`return {world_id}, true`). Installing the handler patches the confirm-button check (call at EGS `0x1303FF`, Steam
`0x13078F`, to EGS `0x1118A0`, Steam `0x111C30`) to go through a stub that returns "not pressed" while the lock flag
is set. The card is shown and the player can cancel out, but can't enter the world. The flag is cleared every time
the screen is set up.

A locked card is also dimmed. Every frame the screen sets each card's brightness with `(y + 75) * 0.35 / 150 + 0.65`
(back cards are darker) through a color setter (EGS `0x248290`, Steam `0x2486E0`) that writes the card's RGB
multiplier at `+0x110`. Its call (EGS `0x130A68`, Steam `0x130DF8`) goes through a stub that multiplies the
brightness by 0.4 while the lock flag is set.

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
