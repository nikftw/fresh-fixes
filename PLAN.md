# Fresh Fixes — Addon Plan (living spec)

Target client: **WoW Forever 1.60.1.70291**, TOC Interface **16001** (retail-style API, incl. Midnight "secret values").
Audience: our guild only; everyone is assumed to run Fresh Fixes + BigWigs.

Install: the **`FreshFixes`** folder lives in `World of Warcraft/_classic_beta_/Interface/AddOns/`.
After every change: `python tools/sync.py` mirrors the desktop copy into the game folder.
`/ff` opens the settings window: left = modules with on/off switches, right = that module's settings.

UI rules: flat grey surfaces, 1px borders, no Blizzard frame templates. Everything is built from
`FreshFixes/Skin.lua` (theme, fonts, buttons, switches, sliders, dropdowns, inputs, colour swatches,
scroll areas, windows, on-screen displays) and modules describe settings with `FF.Settings(key, fn)`.

## Forever API facts

- `issecretvalue()` and `C_Secrets.ShouldAurasBeSecret()` exist → aura/unit data can be
  secret (unreadable) in combat. Every read of combat data goes through `FF.readable()`.
- `UnitFullName(unit)` returns **first name, surname, realm**. Identity key = `"First Surname-Realm"`,
  whitespace stripped, lowercased. Never match on first name only.
- `C_ChatInfo.SendAddonMessageLogged` + `Enum.SendAddonMessageResult` are present.
- `C_EncodingUtil` (JSON, compress, base64) confirmed; `Enum.CompressionMethod.Zlib = 1`.

## Architecture

```
FreshFixes/
  Core.lua      events, identity, saved vars, module loader, /ff
  Codec.lua     !FF:<KIND>:<SCHEMA>! strings (C_EncodingUtil, no libraries)
  Comms.lua     one addon prefix, chunking, throttle
  TextBox.lua   copy/paste window
  UI.lua        shared list window
  Group.lua     group helpers + guild roster cache
  Options.lua   /ff options window
  Media/ring.tga
  Modules/      one file per feature
```

- **One addon folder.** Each module's code only registers an init function; it runs at login only if the
  module is enabled. A disabled module creates no frames, events, tables or saved data.
- No Ace3. One shared event frame; small per-module frames only for player-only unit events.
- One comms prefix `FFIXES`; message = `<tag>~<payload>`. Tags: K nicknames, C consumes, D cooldowns,
  G gear, Y resurrections. (Reminders and interrupts moved to the Speedrun WeakAura.)
- SavedVariables `FreshFixesDB`: only non-default values are written.

## Modules (all built; syntax-checked, unit/smoke-tested against a mocked API, not yet tested in game)

| Module | Commands | Notes |
|---|---|---|
| Nicknames | `/ff nick` | One nickname per player + alts, BattleTag entries, guild sync, leader send/request with trust list; Blizzard raid frames, EllesmereUI, ElvUI tags, Grid2 status, VuhDo bars, tooltips, WeakAuras names |
| Group Setup | `/ff group` | Layouts: import, apply, export (two-word names, realms, nicknames). Assistants: everyone / list / guild rank. Always-mark players (MRT style). Whisper-keyword invites |
| Consumes | `/ff cons` | Flask/elixir/food/weapon (+ expiring), healthstone, raid buffs, durability; clickable consumables bar; lead summary |
| Gear Check | `/ff gear` | Missing enchants / gems / empty slots + item level on ready check; lead summary; raid window |
| Raid Cooldowns | `/ff cd` | Self-reported raid CDs (Forever spell list checked on Wowhead), spell icon per row, columns x rows grid, MRT-style sort rules + ready-first + reverse |
| Quality of Life | `/ff`, `/ff qol` | ~55 Leatrix Plus toggles (automation, social, chat, interface, tooltip, system) |
| Map | `/ff` | Unexplored-area reveal; flight points, instances, spirit healers, boats/zeppelins/trams, portals, zone crossings; map scale, no fade, unlock |
| Mouse Ring | `/ff ring` | Ring at cursor (combat-only by default), GCD swipe, class color |
| Co-Tank Frame | `/ff cotank` | Other tank's health, target, debuffs (game-rendered when available) |
| Summons | `/ff sum` | Ritual of Summoning announce; "123" queue window for warlocks |
| Resurrections | settings | After a boss: caster > target res bars, still-dead list; announces your own res in raid chat (+ optional whisper) |
| Waypoints | `/ff way` | Built-in in-world waypoint (flat marker + distance, edge arrow off screen) following the RXP guide step; no WaypointUI needed. Art: tools/gen_waypoint_art.py |
| Import & Export | `/ff prof`, `/ff guild` | Setting profiles (per character, share strings); professions export for the website (secure click per profession, nothing saved); guild roster export + notes import with confirmation |

## Source coverage (from `src/`)

Licences: NSRT is "All Rights Reserved", Leatrix and MRT ship no licence, RG Aliases is GPLv2 →
everything was rebuilt from behaviour, no code copied.

| Source feature | Status |
|---|---|
| **RG Aliases**: alias → many chars, BattleTag aliases, text import ("Nick - A B"), send to group / request from leader, accept / always accept / always ignore | Done (Nicknames) |
| RG: Blizzard raid frames, WeakAuras names | Done |
| RG: ElvUI (tags `[ff:name]`, `[ff:name:short]`...), Grid2 (status "Fresh Fixes Nickname"), VuhDo | Done |
| RG: EUI / EllesmereUI | Done - answers EUI's nickname lookup (raid + unit frames); EUI unit frames need EUI's own "Show nicknames" option |
| **NSRT** setup manager: invite + arrange from list, role sort, odd/even split, combat abort, spam protection, export groups | Done (Groups) |
| NSRT nicknames | Done (Nicknames) |
| NSRT ready check consumables (click box, expiring, healthstone), raid buffs, durability | Done (Consumes) |
| NSRT ready check gear checks (enchants, gems, empty slots, ilvl) | Done (Gear) - enchantable slot list adjustable for Forever |
| NSRT tier check, cooldown check, vantus | Not done (retail-specific) |
| NSRT QoL: invite keyword, auto promote, invite guild, convert to raid | Done (Groups) |
| NSRT break timer, pace comparison, player stats, boss timelines/alerts (Midnight bosses) | Not done - BigWigs covers breaks; the rest is retail-boss specific |
| MRT raid cooldowns, battle res | Done (Cooldowns) |
| MRT raid groups, invite tools (rank invite, keyword, auto-promote, everyone assist) | Done (Groups) |
| MRT raid check (food/flask report) | Done (Consumes) |
| MRT reminder module (WA-like triggers), loot history, attendance, marks bar, who pulled, inspect viewer, WA checker | Not done - not in your list |
| **Leatrix Plus** automation, social, chat, text, frames, tooltip (rank/target/hide in combat), system | Done for everything listed below in QoL |
| LTP not done: mute game/mount sound packs (need Leatrix's sound ID tables; `/ff qol mute <id>` works per sound), square minimap / minimap button bag, enhanced dressup, volume slider, pet journal save, raid toggle button, screen borders, player chain, ready timer, Wowhead links, widget top, class-colored frames, bodyguard, transforms, edit mode layout, simple addon list, party sync, restore chat, recent chat window, easy chat resize, combat log tab | Ask if you want any |
| **Leatrix Maps** scale, no fade, unlock | Done (Map). Coordinates removed - Forever's default map has them |
| LTM reveal unexplored areas | Done - generated from Blizzard's WorldMapOverlay tables for build 1.60.1.70291 (`tools/gen_mapdata.py`), all 84 map artworks |
| LTM icons: flight points | Done - generated from Blizzard's TaxiNodes table (76) |
| LTM icons: spirit healers, boats/zeppelins/trams, portals, zone crossings (click to open the zone), dungeon/raid entrances incl. Forever's new ones | Done - imported from Leatrix Maps for Forever (`tools/import_leatrix_icons.py`, 276 icons on 49 zones). |
| LTM hide town icons, battlefield map tweaks | Not done |

## Map data

`FreshFixes/Modules/MapData.lua` is generated from Blizzard's own DB2 tables (CSV from wago.tools) for the
Forever build. After a game patch: download WorldMapOverlay, WorldMapOverlayTile, TaxiNodes and Map for the
new build and run `python tools/gen_mapdata.py <csv folder> FreshFixes/Modules/MapData.lua <build>`.
`FreshFixes/Modules/MapIcons.lua` comes from Leatrix Maps for Forever: after a Leatrix update run
`python tools/import_leatrix_icons.py <_classic_beta_>/Interface/AddOns/Leatrix_Maps/Leatrix_Maps_Icons.lua FreshFixes/Modules/MapIcons.lua`.

## Decisions

- Data formats in **FORMATS.md**: PROF, ROSTER, NICK, GROUP, PROFILE.
- Fojji WAs are our code → ported, restructured (shared roster cache, one prefix, full-identity keys, plain frames).

## Things that may need adjusting on Forever

- Spell/buff IDs: Consumes (flask/elixir IDs) and Cooldowns (spell names) use Classic values. Fix in game:
  `/ff cons buffs` lists your buffs with IDs, `/ff cons add …`, `/ff cd add <Spell> <seconds>`.
- Whisper addon messages to names with surnames.
- Co-tank debuffs that read combat data may be secret in combat.
- Profession recipe API (retail `C_TradeSkillUI` path with classic fallback).

## In-game test checklist

1. Install, log in: no Lua errors; `/ff` opens options listing 14 modules; `/ff modules`.
4. Nicknames: `/ff nick Name` → guildmate sees it in your tooltip.
5. Groups: `/ff group save test` in a raid, shuffle someone, `/ff group apply test`.
6. Consumes: ready check with/without flask; lead sees summary.
7. Cooldowns: two players in a group, one casts a tracked spell → window shows the timer.
8. QoL: vendor repair + sell greys; fast loot.
9. Map: coords on world map + minimap; `/ff map scale 0.8`.
10. Mouse ring in combat; `/ff ring 60`.
11. Co-tank: in a group with another tank role, frame shows; `/ff cotank` to move.
12. Summons: warlock casts Ritual → group message; someone types 123 → queue window.
13. `/ff xp`, `/ff camp` with another guildmate online.
14. `/ff roster export`, `/ff roster csv`, `/ff roster import` (officer).
15. Open each profession window, `/ff prof list`, `/ff prof export`.
