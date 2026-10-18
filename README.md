# Fresh Fixes

Guild raid and quality-of-life toolkit for **WoW Forever** (Interface `16001`). Toggle modules in `/ff`, then `/reload` when you turn one on.

## Install

Copy the `FreshFixes` folder into:

`World of Warcraft/_classic_beta_/Interface/AddOns/`

Or from this repo: `python tools/sync.py` mirrors into that path. `/ff` opens settings. Saved variables live in `FreshFixesDB`.

## Modules

| Module | What it does |
| --- | --- |
| **General** | Setting profiles (export/import/share), professions export for the website, guild roster export. |
| **Nicknames** | Guild-shared nicknames on raid frames, groups, and tooltips. |
| **Group Setup** | Import/apply raid layouts, auto-assist, and always-mark players. |
| **Consumes** | Flask/food/weapon buff check on ready check; reports to the lead. |
| **Gear Check** | Missing enchants, gems, empty slots, and item level on ready check. |
| **Raid Cooldowns** | Shared raid cooldown tracking and request alerts between Fresh Fixes users. |
| **Quality of Life** | Auto-repair, sell junk, faster loot, invite filters, and other Leatrix-style tweaks. |
| **Map** | Unexplored tint, map icons, scale/fade, and unlocking the world map. |
| **Graphics** | Visibility-focused graphics presets and CVars (camera, sparkles, self-highlight, and more). |
| **Mouse Ring** | Cursor rings for GCD, cast bar, or spell cooldown, plus trail and melee range warning. |
| **Co-Tank Frame** | Small clickable frame for the other tank. |
| **Summons** | Ritual of Summoning announcements and a `123` summon queue. |
| **Resurrections** | Post-boss bars for who is rezing whom, plus your own res announce. |
| **Drop Cheapest** | On-screen junk icons with vendor price; click or `/ff drop` to delete (greys first). |
| **Blessings** | PallyPower-compatible blessing assignments and a click-to-buff helper. |
| **Auto-mark NPCs** | Mark mobs by NPC ID while hovering with a modifier key held. |
| **Waypoints** | In-world waypoint for the current RestedXP guide step (`/ff way`). |

## Commands

`/ff` — settings · `/ff help` — command list · module commands are listed in each module’s settings tip.
