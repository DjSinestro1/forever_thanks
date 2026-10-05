# forever_thanks

Friendly automatic thank-you whispers and targeted `/thank`-style emotes for
**World of Warcraft: Forever beta 1.60.1**, by Sinestro.

## Features

- Thanks players for newly applied or refreshed helpful buffs whose reported duration is **strictly greater than 120 seconds**.
- Uses 28 varied thank-you messages and avoids repeating the same reply twice in a row.
- Sends a private whisper by default, or a targeted emote without requiring the buff caster to be selected.
- Waits five seconds after detecting a qualifying buff before replying.
- Supports fixed `THANK` emotes or random positive emotes such as Salute, Bow, Wave, Cheer, and Applaud.
- Can suppress whispers when the buff came from a party or raid member while still allowing emotes.
- Includes an ignored-buff list using spell names or spell IDs, useful for buffs such as Campfire.
- Ignores self-buffs, NPC buffs, permanent or unknown-duration effects, short effects such as Renew, and existing buffs restored during login, reloads, portals, or zone/instance transfers.
- Runs out of combat and fails closed when the client hides aura or caster information.
- Settings persist across reloads and logouts.

## Install

Download the release ZIP, not GitHub's source archive. Extract the **forever_thanks** folder into your Forever client's `Interface/AddOns` directory, then restart the client if it was open. Enable `forever_thanks` in the AddOns list. Disable any other automatic thank-you addon to avoid duplicate messages.

The final structure must be:

`Interface/AddOns/forever_thanks/forever_thanks.toc`

## In-game options

Open the settings window with:

`/ft gui`

You can also click the Forever Thanks button at the top-right of the minimap. The options window controls enabling the addon, Whisper or Emote mode, reply delay, cooldown, group behavior, random emotes, custom messages, and ignored buffs. Settings are saved automatically.

## Commands

| Command | Action |
| --- | --- |
| `/ft gui` | Open the in-game options window |
| `/ft status` | Show settings and session diagnostics |
| `/ft on` / `/ft off` | Enable or disable automatic replies |
| `/ft mode whisper` | Send a private whisper; default mode |
| `/ft mode emote` | Send a targeted `THANK` emote |
| `/ft delay 5` | Set the reply delay from 0 to 60 seconds |
| `/ft cooldown 60` | Set the per-player cooldown from 30 to 3600 seconds |
| `/ft groups on` / `/ft groups off` | Allow or suppress all thanks while grouped |
| `/ft groupwhisper on` / `/ft groupwhisper off` | Allow or suppress whispers to party/raid buff casters |
| `/ft emotes thank` / `/ft emotes random` | Choose fixed THANK or random positive emotes |
| `/ft message Thanks for %s!` | Set a custom whisper; `%s` becomes the buff name |
| `/ft message random` | Restore the 28 rotating messages |
| `/ft ignore add <name or ID>` | Add a buff to the ignore list |
| `/ft ignore remove <name or ID>` | Remove a buff from the ignore list |
| `/ft ignore list` | Show ignored buffs |
| `/ft ignore clear` | Clear the ignored-buff list |
| `/ft preview` | Show a local sample without sending anything |
| `/ft debug` | Toggle local chat-attempt diagnostics |

`/foreverthanks` and `/forever_thanks` are aliases for `/ft`.

## Important behavior

The addon intentionally ignores buffs that were already present during login, reload, zoning, or instance transfers so it does not thank everyone nearby for old buffs. New qualifying buffs must be detected while the client is ready and out of combat. Client restrictions, range limits, or unreadable aura data can prevent a reply.

Whispers use the caster's realm-qualified name. Emotes use the caster's plain character name and do not read or change your selected target.

All rights reserved. No affiliation with Blizzard Entertainment.
