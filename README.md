# Friend Filter

Checkboxes for the WoW Forever friends list. Four rulesets (Normal, PvP, Roleplay, RP-PvP), two factions (Alliance, Horde), and one for the Battle.net app.

The boxes sit in a strip along the top of the friends window. If the window is already at the top of the screen, the strip sits under it instead. Every box starts checked, so the list stays as it is. Uncheck PvP to hide friends on PvP. Uncheck Alliance to hide Alliance. Uncheck In App to hide friends who are online in the Battle.net app. Ruleset and faction apply together. Shift-click a ruleset or faction to show only that one.

Friends on retail or another version of WoW are hidden while any ruleset box is unchecked. They are not on a Forever ruleset. Offline friends, and friends in a game other than WoW, stay listed.

While a box is unchecked, a filtered list covers the friends window. Blizzard's search box and Filter menu still apply on top of that. Clicking one of these checkboxes reads Blizzard's list again, including just after the Filter menu updates it. Right-click a friend for the usual menu. Check every box again, or run `/friendfilter reset`, and EllesmereUI's groups and invites come back. The addon does not rebuild Blizzard's list, so whispers stay on Blizzard's link.

## Install

Copy this folder into the Forever client's `Interface/AddOns` directory. The folder name has to stay `friendfilter`.

WowUp can install it too. Select the Forever client, choose Install from URL, and paste `https://github.com/d0ub7/friendfilter`.

`/friendfilter` and `/ffilter` print a short reminder. `/friendfilter reset` checks every box.

## License

[MIT](LICENSE).
