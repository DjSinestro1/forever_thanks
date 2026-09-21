# forever_thanks

Friendly automatic thank-you whispers for **World of Warcraft: Forever beta (1.60.1)**, by Sinestro. Based on the idea and messages from OctoThanks, rebuilt for Forever's aura APIs. This is a beta, not the Turtle/OctoWoW addon.

## Features

- Thanks other players for newly applied or refreshed helpful buffs whose reported duration is **strictly greater than 120 seconds**.
- Eight varied messages, without repeating the previous random message.
- Resolves the actual caster using `C_UnitAuras.GetAuraCasterGUID`, including when `sourceUnit` is nil.
- One-second delay, 60-second per-player cooldown, and at most one whisper attempt every three seconds. Simultaneous excess thanks are dropped, not queued indefinitely.
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
| `/ft on` / `/ft off` | Enable/disable automatic whispers |
| `/ft preview` | Show a sample locally; does not whisper anyone |
| `/ft groups on` / `/ft groups off` | Enable/disable thanks while you are grouped (default on) |
| `/ft cooldown 60` | Per-player cooldown, 30-3600 seconds |
| `/ft message Thanks for %s!` | Custom message; `%s` becomes the buff name |
| `/ft message random` | Restore the eight rotating messages |
| `/ft debug` | Toggle local diagnostics for whisper attempts |

`/foreverthanks` and `/forever_thanks` are aliases for `/ft`.

## Beta limitations and testing

**Out-of-combat only.** Restricted/secret aura information is skipped; the addon never attempts to bypass the client's restrictions. Buffs received during combat are deliberately not thanked later. Unresolvable casters are skipped. WoW may reject a whisper (offline recipient, social restrictions, or future beta API changes); the status counter tracks API requests, not confirmed delivery.

The caster lookup and delayed whisper were tested successfully in Forever 1.60.1. The complete addon has automated mocked-API tests but still needs an in-game end-to-end test.

To test: use `/ft status`, have another player apply a buff longer than two minutes while you are out of combat, and wait one second. Confirm one varied whisper, no repeat for another buff from the same player within 60 seconds, no thanks for your own buffs, and no thanks for Renew. `/reload` should not thank anyone for existing buffs.

## Development

Run `lua5.1 tests/test.lua` from the repository root. `build.ps1` creates an installable ZIP in `dist` using only the runtime files and documentation. No external runtime libraries are required by the addon.

Source and issues: https://github.com/DjSinestro1/forever_thanks

All rights reserved. No affiliation with Blizzard Entertainment.
