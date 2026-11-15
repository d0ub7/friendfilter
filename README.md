# Friend Filter

Checkboxes for the WoW Forever friends list. Four rulesets (Normal, PvP, Roleplay, RP-PvP) and two factions (Alliance, Horde).

The boxes sit in a strip along the top of the friends window. If the window is already at the top of the screen, the strip sits under it instead. Every box starts checked, so the list stays as it is. Uncheck PvP to hide friends on PvP. Uncheck Alliance to hide Alliance. Both apply at once. Shift-click a box to show only that one.

Friends who are offline, in the Battle.net app, or in another game stay listed. They have no ruleset to match.

While a box is unchecked, a filtered list covers the friends window. Right-click a friend for the usual menu. Check every box again, or run `/friendfilter reset`, and EllesmereUI's groups and invites come back. The addon does not rebuild Blizzard's list, so whispers stay on Blizzard's link.

## Install

Copy this folder into the Forever client's `Interface/AddOns` directory. The folder name has to stay `friendfilter`.

WowUp can install it too. Select the Forever client, choose Install from URL, and paste `https://github.com/d0ub7/friendfilter`.

`/friendfilter` and `/ffilter` print a short reminder. `/friendfilter reset` checks every box.
