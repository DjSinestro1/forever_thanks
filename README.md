# forever_thanks

Friendly automatic buff thank-yous for **World of Warcraft: Forever beta 1.60.1**, by Sinestro.

This build defaults to **automatic private whispers** to players who buff you, with an optional built-in THANK emote mode. There is no manual draft or send step. If the client rejects a send, the addon reports the error without retrying the same buff repeatedly.

Automatic say did not work in the user's Forever test. Saved SAY settings migrate to WHISPER; an explicitly selected EMOTE mode persists across reloads. Other preferences are preserved.

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
- `/ft mode whisper` - automatic private replies (default).
- `/ft mode emote` - built-in THANK emote directed at the buff caster.
- `/ft on` / `/ft off` - enable or disable.
- `/ft preview` - local preview only.
- `/ft groups on|off` - thanks while grouped (default on).
- `/ft cooldown 60` - 30-3600 seconds per player.
- `/ft message Thanks for %s!` - custom reply; `%s` inserts the buff name.
- `/ft message random` - restore all 28 replies.
- `/ft debug` - toggle local chat-attempt diagnostics.

`/foreverthanks` and `/forever_thanks` are aliases.

`channel` is an alias for `mode`. Emote mode uses the game's fixed thank-you, not the 28 whisper phrases or custom text. It passes the caster's plain character name (without the realm suffix) to the emote API. It never reads or changes your selected target; you can keep an enemy targeted or have no target. Whispers still use the realm-qualified name.

The user confirmed that a delayed plain-name THANK reaches the intended player after clearing the selected target. The updated addon flow still needs an in-game retest. Range/client restrictions may prevent the intended result. Failed requests do not trigger a whisper fallback or retry. Mode changes cancel pending replies. Emote return values are treated as restriction flags, matching [Blizzard's chat UI](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua).

## Test automatic whispers

Run `/reload` and optionally `/ft debug`. While out of combat, have another player give you a buff longer than two minutes. Wait one second and check for an outgoing whisper. If nothing appears, run `/ft status` and report the output plus any game error. Counters show API requests, not confirmed delivery.

Caster lookup and delayed whisper were previously tested on Forever 1.60.1. The addon does not bypass client restrictions.

Run `lua5.1 tests/test.lua` from the repository root for mocked tests. `build.ps1` creates the installable ZIP.

Source: https://github.com/DjSinestro1/forever_thanks

All rights reserved. No affiliation with Blizzard Entertainment.
