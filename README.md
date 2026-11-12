# forever_thanks

Friendly automatic thank-you whispers and targeted `/thank`-style emotes for
**World of Warcraft: Forever 1.60.1**, by Sinestro.

## Features

- Thanks players for newly applied or refreshed helpful buffs whose reported duration is **strictly greater than five minutes (300 seconds)**. Three-minute Battle Shout and buffs lasting exactly five minutes are ignored.
- Uses 28 varied thank-you messages and avoids repeating the same reply twice in a row.
- Supports custom whispers with `{name}` for the buff caster's character name and `%s` for the buff name.
- Sends a private whisper by default, or a targeted emote without requiring the buff caster to be selected.
- Waits five seconds after detecting a qualifying buff before replying.
- Supports fixed `THANK` emotes or random positive emotes such as Salute, Bow, Wave, Cheer, and Applaud.
- Emotes wait for you to stop moving or falling before choosing a reply, for up to 10 extra seconds after the configured delay. Whispers are not delayed by movement.
- Can suppress whispers when the buff came from a party or raid member while still allowing emotes.
- Includes an ignored-buff list using spell names or spell IDs, useful for buffs such as Campfire.
- Ignores self-buffs, NPC buffs, permanent or unknown-duration effects, short effects such as Renew, and existing buffs restored during login, reloads, portals, or zone/instance transfers.
- Attempts both whisper and emote replies during combat, while still skipping safely when the client hides aura or caster information or blocks the action.
- Includes a saved option to hide the minimap button.
- Settings persist across reloads and logouts.

## Install

Download the release ZIP, not GitHub's source archive. Extract the **forever_thanks** folder into your Forever client's `Interface/AddOns` directory, then restart the client if it was open. Enable `forever_thanks` in the AddOns list. Disable any other automatic thank-you addon to avoid duplicate messages.

The final structure must be:

`Interface/AddOns/forever_thanks/forever_thanks.toc`

## In-game options

Open the settings window with:

`/ft gui`

You can also click the blue Thank You heart button on the minimap's outer edge (bottom-left by default). Drag the button around the minimap to reposition it; its position is saved. The options window controls enabling the addon, Whisper or Emote mode, reply delay, cooldown, group behavior, random emotes, custom messages, and ignored buffs. Settings are saved automatically. Valid delay and cooldown values save as you type; pressing Enter is not required.

Uncheck **Show minimap button** to hide the button. This choice is saved across reloads and logouts. You can always reopen settings with `/ft gui` and show it again.

## Commands

| Command | Action |
| --- | --- |
| `/ft gui` | Open the in-game options window |
| `/ft minimap on` / `/ft minimap off` | Show or hide the minimap button |
| `/ft status` | Show settings and session diagnostics |
| `/ft on` / `/ft off` | Enable or disable automatic replies |
| `/ft mode whisper` | Send a private whisper; default mode |
| `/ft mode emote` | Send a targeted `THANK` emote |
| `/ft delay 5` | Set the reply delay from 0 to 60 seconds |
| `/ft cooldown 60` | Set the per-player cooldown from 30 to 3600 seconds |
| `/ft groups on` / `/ft groups off` | Allow or suppress all thanks while grouped |
| `/ft groupwhisper on` / `/ft groupwhisper off` | Allow or suppress whispers to party/raid buff casters |
| `/ft emotes thank` / `/ft emotes random` | Choose fixed THANK or random positive emotes |
| `/ft message Thank you {name} for the %s!` | Set a custom whisper; `{name}` becomes the caster's name and `%s` becomes the buff name |
| `/ft message random` | Restore the 28 rotating messages |
| `/ft ignore add <name or ID>` | Add a buff to the ignore list |
| `/ft ignore remove <name or ID>` | Remove a buff from the ignore list |
| `/ft ignore list` | Show ignored buffs |
| `/ft ignore clear` | Clear the ignored-buff list |
| `/ft preview` | Show a local sample without sending anything |
| `/ft debug` | Toggle local chat-attempt diagnostics |

`/foreverthanks` and `/forever_thanks` are aliases for `/ft`.

For example, `Thank you {name} for the %s!` becomes `Thank you Steamboots for the Blessing of Might!`. This works in the custom-whisper field in `/ft gui` as well as with the message command. Use `/ft preview` to check it locally with example names.

## Important behavior

The addon intentionally ignores buffs that were already present during login, reload, zoning, or instance transfers so it does not thank everyone nearby for old buffs. New qualifying buffs must be detected while the client is ready. Combat does not automatically cancel a reply, but client restrictions, range limits, or unreadable aura data can still prevent it. Blocked actions are not repeatedly retried.

Emotes are selected only after the player is confirmed stationary and not falling. While moving, the addon waits up to 10 additional seconds after the normal reply delay, then discards the reply instead of sending a stale thank-you. If movement information is unavailable or hidden, it uses the same bounded wait. This does not guarantee that the client will play an animation or deliver the emote.

Whispers use the caster's realm-qualified name. Emotes use the caster's plain character name and do not read or change your selected target.

All rights reserved. No affiliation with Blizzard Entertainment.
