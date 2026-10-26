# GridForge 1.0 (grandMA3)

Selection Grid tools. They work on the CURRENT selection, keep the selection order, rebuild it with the grid cursor and check every position.

| Tool | What it does |
|---|---|
| Matrix | columns, spacing X / Y, extra gap every N, snake, fill by rows or columns |
| Diagonal | Line / Zigzag / Blocks, 4 directions, start at first or last, step X / Y |
| Ring | circle, radius auto or typed, start side, CW / CCW ; several rings: "Ring sizes" e.g. `1,6,12` (centre out) |
| Mirror | two runs: 1) record the placed half, 2) select the other half, run again |
| Copy | two runs: 1) record a shape, 2) select one or more groups of the same size -> each gets the shape ("Stack on shape" option) |
| Sync | rebuild a combined group from its part groups |
| GridStore | store the selection's grid into the fixture type (Oops does NOT undo this - use Reset) |
| Reset | Grid Auto back to Auto on every geometry of the fixture types in the selection |

- "Only group N": arranges only the fixtures of group N in the selection; the group can keep its place, go right of / below the rest, or "Free".
- Optional: store the result to a group.
- Quick-button arguments: `Plugin "GridForge" "matrix" | "diagonal" | "ring" | "mirror" | "copy" | "sync" | "gridstore" | "reset"`.
- Log: `gma3_library\GF_report.txt` (every run is added at the end; delete the file for a fresh log).

Files: `GridForge.lua` + `GridForge.xml`.
