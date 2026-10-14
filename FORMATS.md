# Fresh Fixes — Data Formats (v1)

Shared by the addon and the FF website. Change a schema → bump its number; the addon
refuses schemas newer than it knows and upgrades older ones.

## Envelope

```
!FF:<KIND>:<SCHEMA>!<base64( zlib( JSON ) )>
```

| Part | Meaning |
|---|---|
| `KIND` | `PROF` professions · `ROSTER` guild roster · `NICK` nicknames · `GROUP` raid layout · `PROFILE` settings profile |
| `SCHEMA` | integer schema version of that kind, starts at `1` |
| body | UTF-8 JSON → zlib (RFC 1950) → standard Base64 (`+/=`) |

In game: `C_EncodingUtil.SerializeJSON` → `CompressString(…, Enum.CompressionMethod.Zlib)` → `EncodeBase64`.

Website decode (JS):
```js
const [, kind, schema, b64] = str.trim().match(/^!FF:([A-Z]+):(\d+)!(.+)$/s);
const bytes = Uint8Array.from(atob(b64.replace(/\s/g, "")), c => c.charCodeAt(0));
const json = await new Response(new Blob([bytes]).stream()
  .pipeThrough(new DecompressionStream("deflate"))).text();
const data = JSON.parse(json);
```
Encode is the reverse (`CompressionStream("deflate")` → base64 → prepend header).

Conventions:
- **Character identity** = `"First Surname-Realm"` exactly as the game displays it (Forever names have surnames). Matching is case- and whitespace-insensitive.
- Timestamps are Unix seconds (server time). Durations are seconds.
- Lua cannot tell an empty array from an empty object: treat `{}` and `[]` as equal and omit empty lists where possible.
- Unknown fields must be preserved/ignored, never rejected.

---

## PROF:1 — Professions (one or more characters)

```json
{
  "exported": 1760000000,
  "addon": "0.1.0",
  "characters": [
    {
      "name": "Fojji Ashmane-Forever",
      "class": "WARLOCK",
      "race": "Orc",
      "level": 42,
      "faction": "Horde",
      "guild": "Fresh Fixes",
      "professions": [
        {
          "skillLine": 171,
          "name": "Alchemy",
          "rank": 150,
          "max": 225,
          "scanned": 1759990000,
          "recipes": [2329, 2330, 3170]
        }
      ]
    }
  ]
}
```
`recipes` = recipe spell IDs (map to Wowhead/DB on the site). The addon exports the logged-in
character only (one entry in `characters`); the site merges characters. A profession has no
`recipes` when it has no recipe list (gathering) or couldn't be opened.

---

## ROSTER:1 — Guild roster

```json
{ "guild": "Fresh Fixes", "exported": 1760000000,
  "members": [ { "name": "Fojji Ashmane-Forever", "rank": "Officer", "rankIndex": 1, "level": 60,
                 "class": "WARLOCK", "note": "main", "officerNote": "" } ] }
```

Export lists every member (sorted by rank, then name). Import reads the same shape and only uses
`name`, `note` and `officerNote`: changed notes are listed for confirmation, then applied
(public notes / officer notes only if your rank may edit them).

---

## NICK:1 — Nicknames

```json
{ "from": "Nik Palatoo", "nicknames": [ { "name": "Fojji Ashmane", "nick": "Fojji" }, { "name": "Name#1234", "nick": "Bob" } ] }
```
- `name` is the character's "First Surname" (WoW Forever has no realms; a `-Realm` suffix is
  accepted and ignored, as is the surname arriving in the realm slot, `First-Surname`).
  A BattleTag covers every character of that Battle.net friend.
- `from` is the sender's own "First Surname"; receivers use it to check the sender's guild rank.
- Lists from officers / the GM (GM, ranks 0-1, or any rank that can read officer chat or notes)
  replace existing entries; lists from anyone else only add characters the receiver doesn't have.
- Nicknames are 1–24 characters.

---

## GROUP:1 — Raid group layout

```json
{ "name": "Mythic Vexie", "groups": [ ["Fojji Ashmane-Forever", "Shane"], [], [], [], [], [], [], [] ] }
```
`groups` = up to 8 arrays of up to 5 names. Names can be "First Surname-Realm", "First Surname", a nickname,
or a first name (only if one raid member has it). The addon keeps an imported layout in memory until it's applied;
`/ff group` Export produces this format from the raid's current groups.

In-game text form (`/ff group new`):
```
name: Mythic Vexie
1: Fojji, Shane, Tankyboy
2: ...
```

## PROFILE:1 - settings profile

`!FF:PROFILE:1!...` decodes to:

```json
{ "name": "Raid setup", "author": "Fojji", "settings": { "<dbKey>": { "<setting>": "value" } } }
```

`settings` mirrors `FreshFixesDB` (core = module switches + positions, then one table per module).
Shared data is never included (nicknames, professions, roster caches).
JSON keys must be strings, so number keys are sent as `"#<n>"` (e.g. `marks = { "#3": "Bob" }`) and restored on import.
Importing always creates a new profile (name gets " 2", " 3"... if taken).
