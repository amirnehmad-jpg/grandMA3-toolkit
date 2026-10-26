---
name: grandma3-lua
description: Writing, fixing or reviewing grandMA3 Lua plugins and macros (onPC / console 2.5.x) - objects, commands, macros and variables, sequences / recipes / cues, presets, fixture types and channel sets, gobo pictures, appearances and images, layouts, masters. Load it before writing MA3 plugin code or answering how grandMA3 behaves.
---

# grandMA3 Lua - how to work

Read `ma-facts.md` (next to this file) for the facts that were VERIFIED on a console. Everything else: probe, do not guess.

## Rules that save hours
1. **Probe first.** Unknown MA behaviour = a small read-only plugin that logs what it finds (properties, children, read-backs) to a text file in `gma3_library`. Never present an untested command as known.
2. **Every failed `Cmd()` shows an error pop-up** on the console. Test values through the Lua API (`h:Set` in `pcall`) and read them back; guard deletes with an existence check.
3. **Log everything**: every command with its result (`CMD <command> -> <result>`), a last `RESULT` line. The user runs, you read the log. Wrap the run in `xpcall(fn, debug.traceback)` so an error is logged too.
4. **Read property names, do not guess them**: `h:PropertyCount()` / `h:PropertyName(i)` / `h:Get(name)` in pcall. Dump an object once, then write the code.
5. **Lua 5.5** (grandMA3 2.5.1): assigning to a `for` loop variable is a COMPILE error - the plugin then says "no reference to main function found". Check every file with a real Lua 5.5 (`assert(loadfile(file))`) before giving it to the user.
6. Max 200 locals at file level; file-level locals survive between runs of the same plugin (reset state in main).
7. Long builds: `pcall(coroutine.yield, sec)` now and then, ~60 addresses per command line, one `CreateUndo` / `CloseUndo` so everything is one Oops.
8. Never `Delete ... Thru ...` over numbers that are not all yours. Check ownership by name before overwriting.
9. Do not run MA's internal `startshow_import` plugin (it deletes files in gma3_library).
10. Plugins go in the ROOT of `gma3_library/datapools/plugins` (a subfolder import is not saved in the show). An imported plugin is not refreshed when its file changes: delete it from the pool and import the xml again (or run the newest file from disk through a small loader plugin with `loadfile`).

## Show-time engines without Lua (patterns that work)
- Buttons = macros; state = user variables (`SetUserVariable`, `$VAR`); conditions = tags + `If Tag` (keep one "park" object with the tag in every list).
- Choices = small "picker" sequences (one cue per choice, the cue command does the work, layout element Action = Goto, `PreferCueAppearance` for per-cue pictures).
- A recipe that references a MAtricks object follows it live: keep a "prep" MAtricks the buttons edit and a "live" one the recipes use; FIRE copies prep -> live.
- Switch many macro lines at once: tag the lines, `Set Macro a Thru b.* Property "Enabled" "No" If Tag "T"` (LIVE / BLIND, axis X / Y).
