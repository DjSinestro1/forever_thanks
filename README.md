# forever_thanks

Friendly automatic thank-you messages for **World of Warcraft: Forever beta (1.60.1)**, by Sinestro. Based on the idea and messages from OctoThanks, rebuilt for Forever's aura APIs. This is a beta, not the Turtle/OctoWoW addon.

Uses **say by default**, so nearby players can hear your thanks. Use `/ft channel whisper` for private thanks to the caster, or `/ft channel say` to switch back. The choice is saved across reloads. Existing settings without a channel default to say.

**Outdoor say requires your input:** a qualifying buff creates a local prompt. Type `/ft send`, then press Enter to submit the prepared message. The draft expires after 30 seconds. Say inside instances is attempted automatically where allowed; whisper remains automatic. This respects modern WoW's chat restrictions rather than repeatedly attempting a blocked outdoor send.

## Features

- Thanks other players for newly applied or refreshed helpful buffs whose reported duration is **strictly greater than 120 seconds**.
- 28 varied messages, without repeating the previous random message. Includes playful British/Cockney, modern US street, retro jive-style, Australian, New Zealand, South African, Irish, and Canadian phrasing.
- Resolves the actual caster using `C_UnitAuras.GetAuraCasterGUID`, including when `sourceUnit` is nil.
- One-second delay, 60-second per-player cooldown, and at most one chat attempt every three seconds. Simultaneous excess thanks are dropped, not queued indefinitely.
- Ignores self-buffs, NPC buffs, permanent/unknown-duration effects, and short effects such as Renew.
- No mass thanks for existing buffs when logging in, reloading, zoning, or leaving combat.
- Saved settings, optional custom message, and local-only preview/diagnostics.

## Install

Download the release ZIP (not GitHub's source archive). Extract the **forever_thanks** folder into your Forever client's `Interface/AddOns` directory, then restart the client if it was open. Enable forever_thanks in the AddOns list. Disable any other auto-thanks addon to avoid duplicate messages.

The final structure must be `Interface/AddOns/forever_thanks/forever_thanks.toc`.

## Commands

| Command | Action |
| --- | --- |
| `/ft status` | Settings and session diagnostics |
| `/ft send` | Open a pending outdoor say draft; press Enter to submit |
| `/ft on` / `/ft off` | Enable/disable automatic thanks |
| `/ft channel say` / `/ft channel whisper` | Select public say (default) or private whisper |
| `/ft preview` | Show a sample locally; does not whisper anyone |
| `/ft groups on` / `/ft groups off` | Enable/disable thanks while you are grouped (default on) |
| `/ft cooldown 60` | Per-player cooldown, 30-3600 seconds |
| `/ft message Thanks for %s!` | Custom message; `%s` becomes the buff name |
| `/ft message random` | Restore the 28 rotating messages |
| `/ft debug` | Toggle local diagnostics for whisper attempts |

`/foreverthanks` and `/forever_thanks` are aliases for `/ft`.

## Beta limitations and testing

**Out-of-combat only.** Restricted/secret aura information is skipped; the addon never attempts to bypass the client's restrictions. Buffs received during combat are deliberately not thanked later. Unresolvable casters are skipped. WoW may reject automatic chat (channel restrictions, offline whisper recipients, or future beta API changes); the status counter tracks API requests, not confirmed delivery. Say support has mocked-API tests but still needs an in-game check.

The caster lookup and delayed whisper were tested successfully in Forever 1.60.1. The complete addon has automated mocked-API tests but still needs an in-game end-to-end test.

To test: use `/ft status`, have another player apply a buff longer than two minutes while you are out of combat, and wait one second. Outdoors, expect a local prompt: use `/ft send` and press Enter. Check no repeat prompt within 60 seconds, no thanks for your own buffs or Renew, and none on `/reload`. Then select whisper, wait for the cooldown, and test another buff; the thanks should be private and automatic.

## Development

Run `lua5.1 tests/test.lua` from the repository root. `build.ps1` creates an installable ZIP in `dist` using only the runtime files and documentation. No external runtime libraries are required by the addon.

Source and issues: https://github.com/DjSinestro1/forever_thanks

All rights reserved. No affiliation with Blizzard Entertainment.
