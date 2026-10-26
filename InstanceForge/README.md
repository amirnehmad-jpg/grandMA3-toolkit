# InstanceForge 4.7 (grandMA3)

Automatic groups for multi-instance fixtures.

- Reads the sub-fixture tree of the first fixture of a range. The instance TYPES come from the geometry names of the fixture profile:
  `[Head 7]` -> Head, `[Ring 3 CW]` -> Ring CW, `[P5 Zone2]` -> Zone 2 (running numbers are dropped, numbers that repeat are categories and are kept).
- One group per type, for all fixtures of the same type and mode, fixture by fixture. Groups are stored as a matrix (one row per fixture).
- Options: **Linear groups** (the same groups as one line, "... Line") and **Template groups** (the first fixture only; for "All" types also a
  "Unit" template = the parts of the first container: arrange it small with GridForge, then GridForge Copy it to the other fixtures).
- It opens with a list of Groups 1-8 that exist (pick one and its fixtures are taken), or "Type a fixture range".
  New groups are numbered from "Start Group" (the first free number after your highest group). "BuskDFX group" stays empty unless you use BuskDFX.
- Report: `gma3_library\IF3_report.txt` (appended, with date and time). Everything is one Oops.
- Test mode: `Plugin "InstanceForge" "test"`.

Files: `InstanceForge47.lua` + `InstanceForge47.xml` (MA shows the name as "InstanceForge 47": it does not allow the dot).
