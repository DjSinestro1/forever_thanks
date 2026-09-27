# forever_thanks

Friendly automatic buff thank-yous for **World of Warcraft: Forever beta 1.60.1**, by Sinestro.

This build sends **automatic private whispers** to players who buff you. There is no manual draft or send step. If the client rejects a send, the addon reports the error without retrying the same buff repeatedly.

Automatic say did not work in the user's Forever test. This version restores whispers and automatically migrates saved SAY settings on load. Other preferences are preserved.

## Features

- Only helpful player buffs whose reported duration is **strictly greater than 120 seconds** qualify.
- 28 rotating friendly replies with no consecutive random repeats, including slang-inspired English phrases.
- Resolves casters via `C_UnitAuras.GetAuraCasterGUID`, including when `sourceUnit` is nil.
- One-second delay, 60-second per-player cooldown, and at most one chat attempt every three seconds.
- Ignores self-buffs, NPCs, permanent/unknown-duration effects, short HoTs, and existing buffs on login/reload/zoning/combat exit.
- Out of combat only. Restricted/secret aura information and unresolved casters are skipped.

## Install and commands

Extract `forever_thanks` into your Forever client's `Interface/AddOns` directory. Restart the client if adding it for the first time, or use `/reload` after updating. Disable any other auto-thanks addon to avoid duplicate replies.

- `/ft status` - selected channel and diagnostics.
- `/ft on` / `/ft off` - enable or disable.
- `/ft preview` - local preview only.
- `/ft groups on|off` - thanks while grouped (default on).
- `/ft cooldown 60` - 30-3600 seconds per player.
- `/ft message Thanks for %s!` - custom reply; `%s` inserts the buff name.
- `/ft message random` - restore all 28 replies.
- `/ft debug` - toggle local chat-attempt diagnostics.

`/foreverthanks` and `/forever_thanks` are aliases.

## Test automatic whispers

Run `/reload` and optionally `/ft debug`. While out of combat, have another player give you a buff longer than two minutes. Wait one second and check for an outgoing whisper. If nothing appears, run `/ft status` and report the output plus any game error. Counters show API requests, not confirmed delivery.

Caster lookup and delayed whisper were previously tested on Forever 1.60.1. The addon does not bypass client restrictions.

Run `lua5.1 tests/test.lua` from the repository root for mocked tests. `build.ps1` creates the installable ZIP.

Source: https://github.com/DjSinestro1/forever_thanks

All rights reserved. No affiliation with Blizzard Entertainment.
