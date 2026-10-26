# grandMA3 Toolkit

Free grandMA3 Lua plugins, plus a Claude Code skill with grandMA3 Lua knowledge.

**Concept, design and testing: Amir Nehmad. Code: Claude (Anthropic), with Amir.** Free to use and share.

| Folder | What it is |
|---|---|
| `InstanceForge/` | **InstanceForge 4.7**: makes groups for multi-instance fixtures automatically (one group per instance type: heads, rings, zones, pixels...). |
| `GridForge/` | **GridForge 1.0**: selection grid tools (Matrix, Diagonal, Ring, Mirror, Copy, Sync, GridStore, Reset). |
| `skills/grandma3-lua/` | A **Claude Code skill**: verified grandMA3 Lua and command facts, for anyone who writes MA3 plugins with Claude. |

Tested on grandMA3 onPC 2.5.0.3 and 2.5.1.x (2.5.1 runs Lua 5.5; both plugins load there).

## Download

Green **Code** button > **Download ZIP**, or the newest file under **Releases** on the right.

## Install a plugin

1. Copy the plugin's `.lua` and `.xml` into the ROOT of the plugins folder, not into a subfolder:
   `C:\ProgramData\MALightingTechnology\gma3_library\datapools\plugins\`
   (on a console: the same `gma3_library/datapools/plugins` on the USB stick / internal drive).
2. In grandMA3, open the Plugins pool, edit an empty plugin and **Import** the `.xml`.
3. Run it: tap the plugin. Arguments for quick buttons are listed at the top of each `.lua` file.

A new version: delete the old plugin from the pool (`Delete Plugin <n>`) and import the new `.xml`.

Each plugin writes a report to `gma3_library` (`IF3_report.txt`, `GF_report.txt`), so you can see what it did.

## Install the skill (Claude Code users)

Copy the folder `skills/grandma3-lua` to `%USERPROFILE%\.claude\skills\` (Windows) or `~/.claude/skills/` (Mac / Linux).
Claude loads it by itself when you work on grandMA3 Lua.

## Notes

- Everything a plugin does is one Oops.
- Save your show before trying a tool for the first time.
- Questions and ideas: send them to Amir.
