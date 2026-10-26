# grandMA3 facts verified on a console (onPC 2.5.0.3 and 2.5.1.x)

Only what a probe or a build log showed. "UNTESTED" = never run on a console. When something is not here: probe it.

## Lua plugin basics
- Chunk: `local pluginName, componentName, signalTable, myHandle = select(1, ...)`, `return main` with `main(displayHandle, argument)`.
  `myHandle:Parent().no` = the plugin's pool number (to call itself: `Plugin <no> "arg"` from a macro line).
- File-level locals persist between runs of the same plugin; reset state inside main. Max 200 locals at file level.
- `Cmd(cmd, undo)` is blocking. Long loops: `pcall(coroutine.yield, sec)`; ~60 addresses per command line. `CreateUndo`/`CloseUndo`.
- Every failed `Cmd()` pops up an error on the console. Try values with `h:Set` in pcall instead. Wrap a whole run in `xpcall(fn, debug.traceback)`.
- `GetPath(Enums.PathType.Library)` + `io.open` for logs. A file left open by a run that died stays locked until MA restarts.
- Lua memory: a table of ~650 000 strings (every property of every cue of a big DataPool) = `not enough memory`. Snapshot only what you need.
- Windows: `MessageBox{title, message, commands={{value,name}}, inputs={{name,value}}, states={{name,state}}, selectors=...}`
  -> `.result`, `.inputs[name]`, `.states[name]`. Inputs show alphabetically. `TextInput(title, default)`. `PopupInput{title, caller=displayHandle, items}` returns index AND name (use the name).
- Selection: `SelectionFirst()` / `SelectionNext(idx)` -> `idx, gridX, gridY, gridZ` (PATCH order); `GetSubfixture(idx)`; `:ToAddr()` -> "Fixture 21.3.1".
- `GetDMXValue` returns nil / -1 on onPC: never verify by DMX.
- Programmer read: `GetProgPhaser(GetUIChannelIndex(SelectionFirst(), GetAttributeIndex("Zoom")), false)[1].absolute` (also `absolute_value`, `channel_function`).

## Objects from Lua
- Children: `parent:Append(class)` (not `Create`): macro line `m:Append()` + `l:Set("Command", c)`; recipe line `part:Append("StandardRecipe")` (no pop-up); empty layout element `layout:Append()`.
- Pool `Create(n)` fails for high numbers -> `Cmd("Store Macro n")` then `pool[n]`.
- Iterate pools with `pool:Ptr(i)` for i = 1..Count, or by number `pool[n]` for n = 1..9999 (a `Ptr(Count)` once came back nil; `pools[i]` on DataPools gave nil).
- Properties: scan `h:PropertyCount()` / `h:PropertyName(i)` for real names, `h:Get(name)` in pcall. Do not guess names.
- `h:HasActivePlayback()` on a sequence works. `ObjectList("Sequence 5")[1]`, `ObjectList("Page 2.111")[1].Object` (what an executor holds).
- User variables: `SetUserVariable "X" value` (command); Lua `GetVar(UserVars(), "X")` reads them. `SetVar` with TEXT + read back works (231 chars); writing a NUMBER with SetVar silently fails (assume).
  `SetUserVariable "X" <tapped object>` stores NOTHING usable (reads nil) - you cannot capture a tapped object in a variable.
  `GlobalVars()` same API (command `SetGlobalVariable`).
- Names: MA DROPS dots from names ("L1.36.1" -> "L1361", cue label "0.25" -> "025"). "Not allowed characters" are changed. Duplicate names get "#2".
  Never read a value back from a name.

## Commands, macros, variables
- Macro lines without `DataPool n` resolve in the SELECTED DataPool, even inside a macro of another pool. Start a macro of another pool with `Go+ DataPool 2 Macro n` (`DataPool 2 Macro n` alone = Illegal object). `Call` ignores `If Tag`.
- `... If Tag "T"` filters the target list. No match at all = "Illegal object" pop-up -> keep a "park" object in every list that always carries the tag.
- Tags on macro LINES: `Assign Tag "T" At Macro 1301.2`; switch many lines: `Set Macro a Thru b.* Property "Enabled" "No" If Tag "T"`.
- `$VAR` unquoted expands (also as object number, as the command word: `$CMD DataPool 3 Sequence $N`). Inside quotes: not expanded. Not inside a variable name. Adjacent numeric vars are ADDED (`$A$B` 2100+30).
- `SetUserVariable "X" (prompt?)` opens a text input window (the `( )` syntax).
- `SetUserVariable "X" At Sequence n Property "SpeedScale"` stores a property in a variable.
- Macro line `Execute` = No (`line:Set("Execute", "No")`): the line is only TYPED into the command line; the next tap on an object completes and runs it, then the macro goes on with the next line. (A plugin macro: line 1 Lua snapshot, line 2 typed `Store`, line 3 Lua finds what the tap made.)
- `Wait` per line: `line:Set("Wait", "0.3")`. Line name: `l:Set("Name", ...)`.
- A macro started from Lua `Cmd("Macro N")` runs asynchronously - wait before reading results.
- Several commands in one line / cue command: ` ; `.
- `Go+ Loaded` fires the FIRST loaded on top (order reversed); `Go+ DataPool N Loaded` does nothing; `Go+ Loaded` with nothing loaded = Illegal object.
- Ranges: `Part 0.1 Thru 3` works, `Part 0.1 Thru 0.3` = Cannot Create Object. `Sequence a Thru b`, `a + b` work. `Master 4.41 Thru 48` works.
- `Store DataPool N` does not change the selected DataPool. DataPool 128 is reserved.
- `Cook` without an option opens a pop-up - never in a cue command.

## Store / Copy with a tap
- Typed `Store` + tap: empty pool slot -> new sequence ; empty executor -> new sequence AND assigned to it ; existing sequence with several cues -> new cue at the end ;
  a sequence with ONE cue -> MA's own window (Overwrite / Merge / Remove / Release / Create Second Cue).
  `Merge` with an empty programmer leaves NO trace (nothing changes) - ask the user which cue.
- `Store <cue> /Remove` removes the programmer values from a cue; part property `OwnDataPresent` says if the cue holds values.
- Typed `Copy <seq> At` + tap: works on an empty POOL slot (copy named "<name>#2"...), on an empty executor answers OK but assigns NOTHING.
- `Copy MAtricks a At b /Overwrite` keeps recipe references to b but copies a's name -> relabel. Target needs `At DataPool 2 MAtricks b`.
- `Copy Appearance a At b /Overwrite` works.
- Copying a preset inside one DataPool while the original exists: copy gets "#2", relabel only after the original is deleted.

## Sequences, cues, recipes
- Cue `.no` = cue * 1000 (cue 2 -> 2000). CueZero has no 0, the OffCue is the child named "OffCue".
- Cue command = property `Command` on the cue's Part 0 (`ObjectList("Sequence S Cue C Part 0")[1]:Set("Command", c)`), several with ` ; `. Runs on Goto; the OffCue's runs on Off.
  A Goto on a picker from another cue command runs that picker's cue command.
- Recipe line: `Assign Group n / Preset p.n / MAtricks m At Sequence S Cue C Part 0.k`. Lua reads `line:Get("Selection")` (group handle), `Values` (preset), `MAtricks`.
  `Assign Group n At Sequence s Cue 1 Thru Part 0.1` swaps all at once; a running recipe follows.
- Recipe line on / off: property `Enabled` ("Yes"/"No", reads false) - `ACTIVE` changes but does nothing. A disabled line just stops (no fade).
- `SelectionMode` "Normal" (values reach sub-fixtures) / "Strict" (masters only).
- Recipe lines have their own MAtricks fields; writing cue lines at show time freezes the screen 1-2 s (Total Reference Update) - use MAtricks objects.
- A recipe that references a MAtricks object reacts LIVE to changes of it (prep / live MAtricks split).
- Sequence props by command: `Priority` "LTP" / "Swap" / "High"..., `OFFWHENOVERRIDDEN` "No", `SpeedScale` Div2 / One / Mul2 (not Half / x2), `SpeedMaster` = the master's current NAME ("Speed1" silently fails after a rename), `PlaybackMaster` = master name via Lua `seq:Set("PlaybackMaster", name)`, `PreferCueAppearance` (Lua), `Wrap` (scan the property names for "WRAP").
- Cue fade: `CueInFade` (also on `Cue "OffCue"`). `TrigType` Follow on the OffCue.
- Release: a recipe line with a `Specials:Release` preset + MAtricks fades back to what is underneath.
- Off When Overridden: a sequence goes off when another takes ALL its attributes.
- Priority order: Super > Swap > Highest > High > LTP > Low. Swap sits above Highest (a Swap sequence beats Highest).

## Presets, attributes
- Write a value: `Attribute "<logical channel>" At Absolute Decimal24 <dmx>` (sub-function names like `Gobo2PosRotate` are refused -> logical channel). `Attribute "ColorRGB_R" At Absolute Percent n` reaches fixtures AND cells.
- Store: `Store Preset p.n /Global|/Universal|/Selective /Overwrite`; another fixture type joins with `/Global /Merge`. One Global preset holds several types.
  Universal dimmer works across types; Universal ZOOM does NOT (values differ per type) -> zoom Global with every type merged.
- Empty preset check: `GetPresetData(h, false, true)` returns a non-table for an empty preset (AutoCreate / Show Creator can make empty presets).
- Verify a preset by recalling it (`At DataPool 2 Preset p.n` on a group, read the programmer); compare by channel, not by attribute name.
- `Copy [DataPool 1] Preset p.n At DataPool N Preset p.m /Overwrite` works (data identical, MA renames when the name exists).
- `At Gel "book"."gel"` refused only by a group without colour mixing (whole command then reads Failed). `AutoCreate Gel` = Object locked.
- Activation groups drag linked channels into presets (prism rotation brings Prism1/Prism2/Prism2Pos). `Attribute "x" At KnockOut` works but breaks the next write by function name.
- `ToAddr()` of a preset = `DataPool 2.5.<pool>.<no>`.
- Import: `Import DataPool 2 Filter n /File "x.xml" /Path "..." /NoConfirm` (presets the same way).

## Fixture types, channel sets, gobo pictures
- Type of a fixture: `GetSubfixture(idx):Get("FixtureType")` (handle; name matching is unsafe - two types can share a name), mode `tonumber(h:Get("Mode"):match("^(%d+)"))`.
  Types: `Patch().FixtureTypes`.
- Tree: FixtureType -> child "DMXModes" -> mode[modeIdx] -> [1] = DMX channels -> DMXChannel -> LogicalChannel (name = attribute family, e.g. "Gobo1") -> ChannelFunction
  (`Attribute`, `DMXFrom`/`DMXTo` 24 bit, `PhysicalFrom/To`, `ModeMaster`/`ModeFrom`/`ModeTo`, `Wheel`) -> ChannelSet (`name`, `DMXFrom`, `DMXTo`).
- A rotating gobo's channel set name ends with "<>". Restricted function = ModeMaster set and not full range.
- Gobo picture: the channel function's `Wheel` -> slot (match the set name: exact, loose, prefix, same index, number "Gobo 3" -> "G03 (Cross)") -> slot `MediaFileName`
  -> image in `ShowData().MediaPools.Gobos` whose name contains the file's base name; else `slot:Get("Image")`. Put it on an appearance: `ap.Image = imgHandle`.
  MegaPointe: sets "Gobo 1..10" vs slots "G01 (MultiDots)..."; rotating sets "Gobo N - Rotation".
- Masters / sub-fixtures: values to a master reach sub-fixtures in Normal mode. Selecting a module's IF group keeps the value on that module. `Down` goes one level.
- Group handle `:Count()` = 0 - count by selecting. `Grid x/y/0` + `Fixture a Fixture b` stores positions; `Fixture N.` = parent + descendants.

## Images, appearances, symbols
- Own PNGs: `gma3_library/media/images/<folder>/` + an `.xml` sidecar (`<UserImage FileName="x.png" FilePath="<folder>"/>`).
  Import: `cd Root`, `cd ShowData.MediaPools.Images`, `list lib`, `Import Image "Images".N /File "x.png.xml" /Path "<abs>" /NC`, `cd Root`. Name becomes `[x_png]`.
  Re-import: `Delete Image "Images".N /NoConfirm` first. Make PNGs with PowerShell System.Drawing (128x128, transparent, white).
- MA symbols: `Image 2.<n>` (pool 2 = Symbols), names like `[number_1_white_png]`, files in `gma3_2.5.1\shared\resource\lib_symbols\symbols\` (number_N_white / _black, calculator_white, arrows...).
  Find one: from a known appearance `ap:Get("Image"):Parent()` = the pool, then by name. Set: `ap:Set("Image", handle)` works (read back the name).
- Appearances: `ShowData().Appearances[n]` (global, not DataPool). Props IMAGE, IMAGEMODE ("Stretch"/"Bar"), IMAGER/G/B/ALPHA, BACKR/G/B/ALPHA. `h.Image = handle`, `h.BackR = 0..255` from Lua.
  `Assign Appearance "Name" At Macro a + b If Tag "T"` (by name or number). `Set Appearance a Property "Color" At Appearance b` copies only the image tint.
  Tags work on appearances. Setting `el.appearance` of a LAYOUT ELEMENT from Lua did not work: use `Assign Appearance n At Layout L.<i>`.
- A sequence on a layout shows its own appearance while off, the cue's while on when `PreferCueAppearance` = true (per-cue pictures: beat / width / speed pickers).
- Custom text over a picture appearance is unreadable; text-only button at size 12 is readable.
- MA's StartShow appearances can be used by name: "Dimmer Phaser XGroup 2" / "... 2 Active" (white / black number symbols), "Dimmer Phaser XGroup 0", "... INPUT" (calculator). Read their properties from Lua before using them.

## Layouts
- `Store Layout N`, `Assign Macro M At Layout N` -> new element = `layout[layout:Count()]`. Props `PosX`, `PosY` (bottom edge, Y grows UP -> negative rows), `Width`, `Height`,
  `CustomTextText` / `CustomTextSize` / `CustomTextAlignmentH/V` ("Center") / `CustomTextColor`, `VisibilityObjectName`, `VisibilityBar`, `VisibilityIndicatorBar`, `VisibilityBorder`, `BorderSize`, `BorderColor` "RRGGBBFF", `Action`.
- Sequence element `Action` "Goto" (reads back a number) -> tapping opens the Goto list; "Go+" works too. `Set Layout 104.1 Thru n Property "Action" "Goto"/"Load"`.
- Empty element (frame / title, like StartShow's "XGroup" boxes): `layout:Append()` + PosX/Y/Width/Height + `CustomTextText` + `BorderSize 1`.
- `layout.CanvasAppearance = appearance` (black canvas). A layout in DataPool 1 shows objects of DataPool 2; element object reads "DataPool 2.9.n" (7 Sequences, 9 Macros, 11 MAtricks).
- StartShow's user profile gives new elements its own defaults - reset them (layout_element_defaults.xml of the MA install) before a plugin builds layouts.

## Masters, executors, pages, MIDI
- `ShowData().Masters`: Selected, Grand, Speed (Master 3.n), Playback (Master 4.n), Timing. Playback Masters 41-48 = the group faders; a sequence takes one via `seq:Set("PlaybackMaster", <name>)` (a handle is ignored).
  `Assign Appearance n At Master 4.41` works (screen colour; hardware LED untested). `Learn Master 3.1` = tap tempo, `Master 3.1 At BPM 120`.
- Group masters: Positive / Negative / Scaling / Additive (good as limiters ; a Playback Master scales only its sequences).
- Page children: `page:Children()` (sparse; `page[i]` gives nil). Executor references in page xml are by NAME.
- A MIDI remote cannot take an executor (Cannot Create Object), only objects.
- Executor buttons have press and release functions.

## Views, setup, export
- `object:Export(dir, file)` works for View, Appearance, Configuration, Layout, Page; `Import View 99 /File .. /Path .. /NoConfirm`.
- Views: `ObjectList("View 1")` (not in DataPool). View buttons: `CurrentProfile().ScreenConfigurations[1][2][screen][button]:Get("OBJECT")`.
- Windows: `ScreenContents`, X / Y / W / H in half cells (screen = 36 x 20).
- System Monitor shows Lua errors with file + line; Command Line History does not.
- `CopyCrashLog If Drive 1` copies crash logs.

## MA's StartShow
- `MA_StartShow.show` (in the MA install, shared\resource\demoshows): groups Grid 1-8, Linear 19-26, Even 37-44, Odd 55-62, thirds 73-116 ;
  presets colours 4.1-4.15, positions 2.1-2.17, Gobo / Prism Rotate Stop / Left / Right 3.19-21 / 5.23-25 ; appearances 4987-5480 ; Layout 4 'Dimmer Phaser'.
  Export it to xml and read it - never guess its numbers.
- If Speed Master 3.1 was renamed, a sequence's `SpeedMaster` must be set by its current name.
- NEVER run `startshow_import` (deletes library files).
