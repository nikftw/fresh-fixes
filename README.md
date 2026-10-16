# Fresh Fixes

Guild raid and quality-of-life addon for WoW Forever (Interface 16001).

## Drop Cheapest (optional, v0.2.0)

Deletes the cheapest junk in your bags, like DropTheCheapestThing: turn on **Drop Cheapest** in `/ff`, `/reload`, then click the bag button (hover to see what it would delete, Shift-drag to move) or type `/ff drop` (`/ff drop show` to preview). Grey items first; anything better asks before deleting; quest items are never touched.

## Blessings (optional, v0.3.0)

PallyPower-style paladin blessings: turn on **Blessings** in `/ff`, `/reload`, then `/ff bless` opens the assignment grid (click a cell to cycle, Shift-click to clear). **Smart** auto-assigns by known blessings and spec (Kings first, Wisdom from Holy, Might from Ret, Sanctuary from Prot). The buff helper lists who is missing your blessing; click a row to cast (right-click: Greater Blessing if known). Uses PallyPower's own `PLPWR` messages (matched to PallyPower Forever v10.15.26-forever), so it works alongside paladins running PallyPower; if PallyPower is installed on your client, this module stays off.

## Install

Copy the `FreshFixes` folder into:

`World of Warcraft/_classic_beta_/Interface/AddOns/`

Then type `/reload` in game. `/ff` opens settings.

Saved variables are stored in `FreshFixesDB`.
