-- ============================================================
--  InstanceForge  v4.7  for grandMA3 (tested on 2.5.0.3)
--  Automatic groups for multi-instance fixtures
-- ------------------------------------------------------------
--  Concept, design & testing : Amir Nehmad
--  Code                      : Claude (Anthropic), with Amir
--  Released: September 2026 - free to use and share
-- ------------------------------------------------------------
--  Reads the sub-fixture tree of the first fixture in a FID
--  range. Instance TYPES come from the geometry names of the
--  fixture profile:  [Head 7] -> Head,  [Ring 3 CW] -> Ring CW,
--  [P5 Zone2] -> Zone 2  (running numbers are removed, numbers
--  that repeat are categories and are kept).
--  One group is stored per type, for all fixtures of the same
--  type and mode, fixture by fixture, in tree order.
--  Everything is one Oops.
--  Type groups are stored as a matrix (one row per fixture).
--  Options (each block after one empty group number):
--    Linear groups   the same groups again as one line ("... Line"),
--                    only for types that are a real matrix
--    Template groups one group per type with the FIRST fixture;
--                    for "All" types also a "Unit" template = the
--                    parts of the first container only (one yoke /
--                    one head) - arrange small -> copy to bigger
--                    only - arrange it with GridForge, then use
--                    GridForge Copy for all the other fixtures
--
--  BuskDFX numbering (v4.4): when the fixtures are found in one of
--  Groups 1-8, the groups go on the 18-wide grid BuskDFX uses:
--    column = instance type (1-17), block of 3 rows per group:
--    row 10 + (g-1)*4 = matrix, next row = Line, next row = Template
--    (G1: 163.. / 181.. / 199..,  G2: 235..,  ... G8: 667..)
--  Leave "BuskDFX group" empty to number freely from "Start Group".
--  v4.5: with BuskDFX numbering and an empty Prefix, the name of that
--  group is the prefix ("JDC Master") - MA keeps no two groups of one
--  name, a second "Master" became "Master#2".
--  The report IF3_report.txt is appended, with date and time.
--  v4.6: the plugin opens with a list of the BuskDFX groups (1-8) that
--  exist, by name: pick one and its fixtures are taken, numbered for
--  that group - no FID range to type. "Type a fixture range" = the
--  dialog of before. No Groups 1-8 in the show: the range dialog.
--
--  Test mode: run with argument "test"  (Plugin "InstanceForge" "test")
--  or run the IF_Test plugin. It builds the ranges in TEST_RANGES
--  without dialogs, verifies every group and writes IF3_test.txt.
-- ============================================================

local pluginName, componentName, signalTable, myHandle = select(1, ...)

local FORCE_TEST  = false
local TEST_RANGES = {
    { first = 1,  last = 10 },
    { first = 11, last = 20 },
    { first = 21, last = 30 },
    { first = 31, last = 40 },
    { first = 41, last = 50 },
}
local TEST_START = 1   -- first group (existing groups are overwritten)
local TEST_GAP   = 3   -- empty group numbers between fixture types
local CHUNK = 60    -- addresses per command line

-- ---------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------
local function safe(f, ...)
    local ok, v = pcall(f, ...)
    if ok then return v end
    return nil
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function fixtureHandle(fid)
    local l = safe(function() return ObjectList("Fixture " .. fid) end)
    return l and l[1] or nil
end

local function prop(h, name)
    local v = safe(function() return h:Get(name, Enums.Roles.Display) end)
    if v == nil then v = safe(function() return h:Get(name) end) end
    return v and trim(v) or ""
end

local function nodeName(h)
    local n = safe(function() return h.name end) or ""
    return trim((tostring(n):gsub("^%[", ""):gsub("%]$", "")))
end

local function children(h)
    local out = {}
    for _, c in ipairs(safe(function() return h:Children() end) or {}) do
        local cls = safe(function() return c:GetClass() end)
        if cls == "SubFixture" or cls == "Fixture" then out[#out + 1] = c end
    end
    return out
end

-- ---------------------------------------------------------------
-- tree of the reference fixture
-- node = { rel = "2.3", depth = 2, name = "Ring 3 CW" }
-- ---------------------------------------------------------------
local function walk(h, rel, depth, list)
    for i, c in ipairs(children(h)) do
        local idx = tonumber(prop(c, "INDEX")) or i
        local r = (rel == "") and tostring(idx) or (rel .. "." .. idx)
        list[#list + 1] = { rel = r, depth = depth, name = nodeName(c), h = c }
        walk(c, r, depth + 1, list)
    end
    return list
end

-- ---------------------------------------------------------------
-- naming: tokens, running numbers vs categories
-- ---------------------------------------------------------------
local function tokenize(s)
    local t, pos, sep = {}, 1, true
    while pos <= #s do
        local sp = s:match("^%s+", pos)
        if sp then
            pos = pos + #sp; sep = true
        else
            local num = s:match("^%d+", pos)
            local tok = num or s:match("^[^%s%d]+", pos)
            t[#t + 1] = { v = tok, num = num ~= nil, glued = (not sep) and #t > 0 }
            pos = pos + #tok; sep = false
        end
    end
    return t
end

local function keyOf(tokens)
    local a, n = {}, 0
    for _, tk in ipairs(tokens) do
        if tk.num then n = n + 1 else a[#a + 1] = tk.v:lower() end
    end
    return table.concat(a, "|") .. "#" .. n
end

-- build a display name from tokens + class of every number slot
local function buildName(tokens, classes)
    local parts, slot = {}, 0
    local drop = {}
    for i, tk in ipairs(tokens) do
        if tk.num then
            slot = slot + 1
            local c = classes[slot]
            if c == "counter" then
                drop[i] = true
                -- short prefix glued to a running number ("P" in P12)
                local prev = tokens[i - 1]
                if tk.glued and prev and not prev.num and #prev.v <= 2 then drop[i - 1] = true end
            end
        end
    end
    slot = 0
    for i, tk in ipairs(tokens) do
        if tk.num then slot = slot + 1 end
        if not drop[i] then
            local c = tk.num and classes[slot] or nil
            if #parts > 0 and tk.glued and c ~= "category" and not drop[i - 1] then
                parts[#parts] = parts[#parts] .. tk.v
            else
                parts[#parts + 1] = tk.v
            end
        end
    end
    local s = trim(table.concat(parts, " "))
    s = s:gsub("%s[%-_/]+%s", " "):gsub("%s[%-_/]+$", ""):gsub("^[%-_/]+%s", ""):gsub("%s%s+", " ")
    s = trim(s)
    return (s ~= "") and s or "Inst"
end

-- nodes -> types { name, rels = {...}, depth }
local function detectTypes(nodes)
    local groups, order = {}, {}
    for _, nd in ipairs(nodes) do
        nd.tokens = tokenize(nd.name)
        local k = nd.depth .. ":" .. keyOf(nd.tokens)
        if not groups[k] then groups[k] = {}; order[#order + 1] = k end
        table.insert(groups[k], nd)
    end

    local types = {}
    for _, k in ipairs(order) do
        local g = groups[k]
        local n = #g
        local numSlots = tonumber(k:match("#(%d+)$")) or 0
        local classes, values = {}, {}
        for s = 1, numSlots do
            local seen, d = {}, 0
            values[s] = {}
            for i, nd in ipairs(g) do
                local c = 0
                for _, tk in ipairs(nd.tokens) do
                    if tk.num then
                        c = c + 1
                        if c == s then
                            values[s][i] = tk.v
                            if not seen[tk.v] then seen[tk.v] = true; d = d + 1 end
                        end
                    end
                end
            end
            if n == 1 then
                -- single instance: drop a standalone trailing number ("Flower 1")
                local last = g[1].tokens[#g[1].tokens]
                local cnt = 0
                for _, tk in ipairs(g[1].tokens) do if tk.num then cnt = cnt + 1 end end
                classes[s] = (s == cnt and last.num and not last.glued) and "counter" or "keep"
            elseif d == n then
                classes[s] = "counter"
            elseif d == 1 then
                classes[s] = "keep"
            else
                classes[s] = "category"
            end
        end
        -- refine "category" slots by the parent (container) of each node:
        --   same value for all children of one parent, different between
        --   parents -> it is the parent's running number ("Pixel 3-5": 3 =
        --   head 3) -> counter. When such a slot exists, a slot whose values
        --   are all different inside every parent is the index inside the
        --   parent ("5" = pixel 5 of the head) -> counter as well.
        -- "Zone 2" (repeats inside one parent) stays a category.
        if numSlots > 0 and n > 1 then
            local parentOf = {}
            for i, nd in ipairs(g) do parentOf[i] = nd.rel:match("^(.*)%.[^%.]+$") or "" end
            local pConst, pDistinct = {}, {}
            for s = 1, numSlots do
                if classes[s] == "category" then
                    local byP, nP, constOK, distOK = {}, 0, true, true
                    for i = 1, n do
                        local pk = parentOf[i]
                        if not byP[pk] then byP[pk] = { first = values[s][i], seen = {} }; nP = nP + 1 end
                        local b = byP[pk]
                        if values[s][i] ~= b.first then constOK = false end
                        if b.seen[values[s][i]] then distOK = false end
                        b.seen[values[s][i]] = true
                    end
                    pConst[s] = constOK and nP > 1
                    pDistinct[s] = distOK and nP > 1
                end
            end
            local anyParentCounter = false
            for s = 1, numSlots do
                if pConst[s] then classes[s] = "counter"; anyParentCounter = true end
            end
            if anyParentCounter then
                for s = 1, numSlots do
                    if classes[s] == "category" and pDistinct[s] then classes[s] = "counter" end
                end
            end
        end
        -- split by category values
        local sub, subOrder = {}, {}
        for i, nd in ipairs(g) do
            local cat = {}
            for s = 1, numSlots do
                if classes[s] == "category" then cat[#cat + 1] = values[s][i] end
            end
            local ck = table.concat(cat, ",")
            if not sub[ck] then sub[ck] = {}; subOrder[#subOrder + 1] = ck end
            table.insert(sub[ck], nd)
        end
        for _, ck in ipairs(subOrder) do
            local list = sub[ck]
            local rels = {}
            for _, nd in ipairs(list) do rels[#rels + 1] = nd.rel end
            types[#types + 1] = {
                name  = buildName(list[1].tokens, classes),
                rels  = rels,
                depth = list[1].depth,
                first = list[1].rel,
            }
        end
    end

    -- keep tree order of first appearance
    local pos = {}
    for i, nd in ipairs(nodes) do pos[nd.rel] = i end
    table.sort(types, function(a, b) return pos[a.first] < pos[b.first] end)

    -- containers whose children are of more than one type get an
    -- extra "<name> All" type: every direct child, in tree order
    -- (e.g. Spiider Zones All = all 19 pixels of the zone matrix)
    local typeOf = {}
    for ti, t in ipairs(types) do
        for _, r in ipairs(t.rels) do typeOf[r] = ti end
    end
    local kids = {}
    for _, nd in ipairs(nodes) do
        local parent = nd.rel:match("^(.*)%.%d+$")
        if parent then
            kids[parent] = kids[parent] or {}
            table.insert(kids[parent], nd.rel)
        end
    end
    local extra = {}
    for ti, t in ipairs(types) do
        local rels, spanned, nSpanned = {}, {}, 0
        for _, r in ipairs(t.rels) do
            for _, c in ipairs(kids[r] or {}) do
                rels[#rels + 1] = c
                local ct = typeOf[c]
                if ct and not spanned[ct] then spanned[ct] = true; nSpanned = nSpanned + 1 end
            end
        end
        if nSpanned > 1 then
            extra[#extra + 1] = { after = ti, t = { name = t.name .. " All", rels = rels,
                                                     depth = t.depth + 1, first = t.first, all = true } }
        end
    end
    for i = #extra, 1, -1 do table.insert(types, extra[i].after + 1, extra[i].t) end

    -- unique names
    local used = { Master = true }
    for _, t in ipairs(types) do
        local base, n = t.name, 1
        if used[t.name] then
            t.name = base .. " L" .. t.depth
            while used[t.name] do n = n + 1; t.name = base .. " " .. n end
        end
        used[t.name] = true
    end
    table.insert(types, 1, { name = "Master", rels = { "" }, depth = 0, cat = 0 })

    -- category + parent for every type
    local byRel, hasKids = {}, {}
    for _, nd in ipairs(nodes) do
        byRel[nd.rel] = nd
        local parent = nd.rel:match("^(.*)%.%d+$")
        if parent then hasKids[parent] = true end
    end
    local typeNameOf = {}
    for _, t in ipairs(types) do
        if not t.all then for _, r in ipairs(t.rels) do typeNameOf[r] = t end end
    end
    for _, t in ipairs(types) do
        local r1 = t.rels[1]
        t.node = byRel[r1]
        local parentRel = t.all and t.first or (r1 or ""):match("^(.*)%.%d+$")
        t.parent = parentRel and typeNameOf[parentRel] or nil
        if t.cat == 0 then
            -- master
        elseif t.all then
            t.cat = 3                                   -- whole matrix
        elseif hasKids[r1] then
            t.cat = 2                                   -- containers / heads
        elseif t.depth == 1 and #t.rels == 1 then
            t.cat = 1                                   -- global parts
        else
            t.cat = 4                                   -- parts / pixels
        end
    end
    -- stable sort by category, then tree order
    for i, t in ipairs(types) do t.ord = i end
    table.sort(types, function(a, b)
        if a.cat ~= b.cat then return a.cat < b.cat end
        return a.ord < b.ord
    end)
    return types
end

-- short attribute summary of one (sub)fixture: "Dimmer, Shutter, ColorRGB"
local function attrSummary(h)
    if not h then return "" end
    local names, seen = {}, {}
    local function add(n)
        if not n or n == "" then return end
        n = tostring(n):gsub("[%d_]+.*$", "")
        if n ~= "" and not seen[n] then seen[n] = true; names[#names + 1] = n end
    end
    local chans = safe(function() return GetUIChannels(h, true) end) or {}
    for _, c in ipairs(chans) do
        local n = safe(function() return c.ATTRIBUTE end)
              or safe(function() return c.attribute end)
              or safe(function() return c:Get("ATTRIBUTE", Enums.Roles.Display) end)
              or safe(function() return c.SUBATTRIBUTE end)
        if type(n) == "userdata" then n = safe(function() return n.name end) end
        add(n)
    end
    if #names == 0 then
        for _, i in ipairs(safe(function() return GetUIChannels(h) end) or {}) do
            local a = safe(function() return GetAttributeByUIChannel(i) end)
            add(a and safe(function() return a.name end))
        end
    end
    if #names == 0 then return (#chans > 0) and ("#" .. #chans .. " ch") or "no channels" end
    local out = {}
    for i = 1, math.min(#names, 4) do out[#out + 1] = names[i] end
    return table.concat(out, ", ") .. ((#names > 4) and " ..." or "")
end

local CAT_TITLE = { [0] = "master", "global", "head", "all", "part" }

local function describe(t, ref)
    local h = (t.cat == 0) and ref or (t.node and t.node.h)
    local where = (t.parent and t.cat ~= 0) and (" in " .. t.parent.name) or ""
    if t.all then return "every part" .. where end
    return attrSummary(h) .. where
end

-- ---------------------------------------------------------------
-- range -> fixtures of the reference type/mode
-- ---------------------------------------------------------------
local function collect(first, last)
    local ref, refKey, fids, skipped = nil, nil, {}, 0
    for fid = first, last do
        local h = fixtureHandle(fid)
        if h then
            local key = prop(h, "FIXTURETYPE") .. " | " .. prop(h, "MODE")
            if not ref then ref, refKey = h, key end
            if key == refKey then fids[#fids + 1] = fid else skipped = skipped + 1 end
        end
    end
    return ref, refKey, fids, skipped
end
-- v4.6: the same from a list of fixture IDs (the fixtures of a group)
local function collectList(list)
    local ref, refKey, fids, skipped = nil, nil, {}, 0
    for _, fid in ipairs(list) do
        local h = fixtureHandle(fid)
        if h then
            local key = prop(h, "FIXTURETYPE") .. " | " .. prop(h, "MODE")
            if not ref then ref, refKey = h, key end
            if key == refKey then fids[#fids + 1] = fid else skipped = skipped + 1 end
        end
    end
    return ref, refKey, fids, skipped
end

-- template rows: first fixture of every type with more than one
-- instance, but not when all of it is already inside a bigger
-- template (Ring CW / Ring WW are inside "Head All")
local function templateRows(list)
    local cands = {}
    for _, g in ipairs(list) do
        if g.row1 and #g.row1 > 1 then cands[#cands + 1] = g end
    end
    local out = {}
    for _, g in ipairs(cands) do
        local inside = false
        for _, o in ipairs(cands) do
            if o ~= g and #o.row1 > #g.row1 then
                local set = {}
                for _, a in ipairs(o.row1) do set[a] = true end
                local all = true
                for _, a in ipairs(g.row1) do if not set[a] then all = false break end end
                if all then inside = true break end
            end
        end
        if not inside then out[#out + 1] = g end
    end
    return out
end

-- templates in build order: for an "All" type (parts of several
-- containers) first the Unit = parts of the FIRST container only
-- (e.g. 21.3.1 .. 21.3.9 = one yoke), then the full template
local function parentRel(rel) return rel:match("^(.*)%.[^%.]+$") or "" end
local function templateList(cands)
    local out = {}
    for _, g in ipairs(templateRows(cands)) do
        local t = g.t
        if t and t.cat == 3 and t.rels and #t.rels > 1 then
            local p1 = parentRel(t.rels[1])
            local unit = {}
            for i, rel in ipairs(t.rels) do
                if parentRel(rel) == p1 then unit[#unit + 1] = g.row1[i] end
            end
            if #unit > 1 and #unit < #g.row1 then
                local base = g.name:gsub("%s+All$", "")
                out[#out + 1] = { name = base .. " Unit", row1 = unit }
            end
        end
        out[#out + 1] = g
    end
    return out
end

-- one list of addresses per fixture (= one row of a matrix)
local function rowsFor(t, fids)
    local rows = {}
    for _, fid in ipairs(fids) do
        local a = {}
        for _, r in ipairs(t.rels) do
            a[#a + 1] = (r == "") and tostring(fid) or (fid .. "." .. r)
        end
        rows[#rows + 1] = a
    end
    return rows
end

local function addressesFor(t, fids)
    local a = {}
    for _, fid in ipairs(fids) do
        for _, r in ipairs(t.rels) do
            a[#a + 1] = (r == "") and tostring(fid) or (fid .. "." .. r)
        end
    end
    return a
end

-- ---------------------------------------------------------------
-- storing
-- ---------------------------------------------------------------
local function groupExists(num)
    return safe(function() return DataPool().Groups[num] end) ~= nil
end

-- give the UI a moment between groups (plugins run as a coroutine)
local PAUSE_CHUNK = 0.05   -- seconds after every command chunk
local PAUSE_GROUP = 0.15   -- seconds after every stored group
local function breathe(t)
    pcall(coroutine.yield, t or PAUSE_GROUP)
end

-- rows = { {addr, addr ...}, ... }  one row per fixture
-- matrix = true : row r goes to grid Y = r-1, instances along X
-- matrix = false: everything in one line
-- The grid cursor advances by itself after every selected fixture.
local function storeGroup(num, name, rows, undo, matrix)
    Cmd("ClearSelection")
    for r, list in ipairs(rows) do
        if matrix then
            Cmd("Grid 0/" .. (r - 1) .. "/0")
        elseif r == 1 then
            Cmd("Grid 0/0/0")
        end
        for i = 1, #list, CHUNK do
            local chunk = {}
            for j = i, math.min(i + CHUNK - 1, #list) do chunk[#chunk + 1] = list[j] end
            Cmd("Fixture " .. table.concat(chunk, " Fixture "))
            breathe(PAUSE_CHUNK)
        end
    end
    Cmd("Store Group " .. num .. " /Overwrite", undo)
    Cmd('Label Group ' .. num .. ' "' .. name:gsub('"', "") .. '"', undo)
end

local function flatten(rows)
    local a = {}
    for _, row in ipairs(rows) do for _, x in ipairs(row) do a[#a + 1] = x end end
    return a
end

-- a group is laid out as a matrix only when it has more than one
-- instance per fixture (otherwise one line, one cell per fixture)
local function useMatrix(rows, matrixOn)
    return matrixOn and rows[1] and #rows[1] > 1 and #rows > 1
end

-- work in selection buffer 2, so the user's selection (buffer 1) stays
local function inBuffer2(fn)
    Cmd("Selection 2")
    Cmd("ClearSelection")
    local ok, err = pcall(fn)
    Cmd("ClearSelection")
    Cmd("Selection 1")
    if not ok then error(err, 0) end
end

-- progress bar helpers (silently ignored if not available)
local function progStart(title, n)
    local h = safe(StartProgress, title)
    if h then safe(SetProgressRange, h, 1, math.max(n, 1)) end
    return h
end
local function progInc(h) if h then safe(IncProgress, h, 1) end end
local function progStop(h) if h then safe(StopProgress, h) end end

-- remembered names per fixture type + mode
local function varKey(refKey)
    return "IF3_" .. refKey:gsub("[^%w]", "_"):sub(1, 60)
end
local function loadNames(refKey)
    local s = safe(function() return GetVar(GlobalVars(), varKey(refKey)) end)
    local map = {}
    for pair in tostring(s or ""):gmatch("[^|]+") do
        local a, b = pair:match("^(.-)=(.*)$")
        if a then map[a] = b end
    end
    return map
end
local function saveNames(refKey, map)
    local t = {}
    for a, b in pairs(map) do t[#t + 1] = a .. "=" .. b end
    safe(function() SetVar(GlobalVars(), varKey(refKey), table.concat(t, "|")) end)
end

-- ---------------------------------------------------------------
-- test mode
-- ---------------------------------------------------------------
local function libDirs()
    local d = {}
    local p = safe(function() return GetPath(Enums.PathType.Library) end)
    if p then d[#d + 1] = p end
    d[#d + 1] = "C:\\ProgramData\\MALightingTechnology\\gma3_library"
    return d
end

local function writeReport(fileName, lines, append)
    for _, dir in ipairs(libDirs()) do
        local sep = dir:find("\\") and "\\" or "/"
        local f = io.open(dir .. sep .. fileName, append and "a" or "w")
        if f then
            f:write(table.concat(lines, "\n"), "\n")
            f:close()
            return dir .. sep .. fileName
        end
    end
    return nil
end

-- select a group and read what it really holds: count + grid size
local function verify(num)
    Cmd("ClearSelection")
    Cmd("Group " .. num)
    local n, maxX, maxY = 0, -1, -1
    local idx, x, y = SelectionFirst()
    while idx and n < 5000 do
        n = n + 1
        if x and x > maxX then maxX = x end
        if y and y > maxY then maxY = y end
        idx, x, y = SelectionNext(idx)
    end
    Cmd("ClearSelection")
    return n, (maxX + 1) .. "x" .. (maxY + 1)
end

local function runTest()
    local rep = {}
    local function r(fmt, ...) rep[#rep + 1] = string.format(fmt, ...) end
    local bd = safe(BuildDetails) or {}
    r("===== InstanceForge MA3 test  (%s %s) =====", tostring(bd.BigVersion), tostring(bd.HostType))
    local undo = CreateUndo("InstanceForge test")
    local prog = progStart("InstanceForge test", 200)
    local num = TEST_START
    inBuffer2(function()
    for _, rg in ipairs(TEST_RANGES) do
        r("")
        r("#### FID %d-%d  -> groups from %d", rg.first, rg.last, num)
        local ref, refKey, fids, skipped = collect(rg.first, rg.last)
        if not ref then
            r("no fixtures")
        else
            -- prefix = fixture type name without its number ("2 CL-1060 WEAVER" -> "CL-1060 WEAVER")
            local ftName = trim((prop(ref, "FIXTURETYPE"):gsub("^%s*%d+%s+", ""))):gsub('"', "")
            local pre = (ftName ~= "") and (ftName .. " ") or ""
            r("type: %s   fixtures: %d   skipped: %d   prefix: '%s'", refKey, #fids, skipped, ftName)
            local nodes = walk(ref, "", 1, {})
            r("--- tree (%d nodes) ---", #nodes)
            for _, nd in ipairs(nodes) do
                r("%s.%-8s %s", string.rep("  ", nd.depth - 1), nd.rel, nd.name)
            end
            local types = detectTypes(nodes)
            local rowTypes = {}
            r("--- types ---")
            for _, t in ipairs(types) do
                local rows = rowsFor(t, fids)
                local addrs = flatten(rows)
                local matrix = useMatrix(rows, true)
                storeGroup(num, pre .. t.name, rows, undo, matrix)
                breathe()
                progInc(prog)
                local got, dims = verify(num)
                local want = matrix and (#rows[1] .. "x" .. #rows) or (#addrs .. "x1")
                local shown = {}
                for j = 1, math.min(#addrs, 6) do shown[#shown + 1] = addrs[j] end
                r("         %-6s %3d/fix  %s", CAT_TITLE[t.cat], #t.rels, describe(t, ref))
                r("Group %d  %-22s expected %4d %-7s selected %4d %-7s %s  | %s%s", num, t.name,
                    #addrs, want, got, dims,
                    (got == #addrs and dims == want) and "OK" or "CHECK",
                    table.concat(shown, " "), (#addrs > 6) and " ..." or "")
                if matrix then rowTypes[#rowTypes + 1] = { name = t.name, rows = rows } end
                num = num + 1
            end
            -- linear groups: the matrix types again as one line
            -- linear groups (one empty number before)
            num = num + 1
            r("--- linear groups from %d ---", num)
            for _, rt in ipairs(rowTypes) do
                storeGroup(num, pre .. rt.name .. " Line", rt.rows, undo, false)
                breathe(PAUSE_CHUNK)
                local got, dims = verify(num)
                local cnt = #flatten(rt.rows)
                local want = cnt .. "x1"
                r("Group %d  %-22s expected %4d %-7s selected %4d %-7s %s  | %s", num, rt.name .. " Line",
                    cnt, want, got, dims, (got == cnt and dims == want) and "OK" or "CHECK", rt.rows[1][1])
                num = num + 1
            end
            num = num + 1
            -- template groups: first fixture of every type with more than one instance
            r("--- template groups from %d ---", num)
            local cands = {}
            for _, t in ipairs(types) do cands[#cands + 1] = { name = t.name, row1 = rowsFor(t, fids)[1], t = t } end
            for _, c in ipairs(templateList(cands)) do
                local t, row = c, c.row1
                do
                    storeGroup(num, pre .. t.name .. " Template", { row }, undo, false)
                    breathe(PAUSE_CHUNK)
                    local got, dims = verify(num)
                    local want = #row .. "x1"
                    r("Group %d  %-22s expected %4d %-7s selected %4d %-7s %s  | %s", num, t.name .. " Template",
                        #row, want, got, dims, (got == #row and dims == want) and "OK" or "CHECK", row[1])
                    num = num + 1
                end
            end
            r("--- last group %d ---", num - 1)
            num = num + TEST_GAP
        end
    end
    end)
    progStop(prog)
    CloseUndo(undo)
    local path = writeReport("IF3_test.txt", rep)
    Printf("InstanceForge test: report " .. tostring(path))
end

-- ---------------------------------------------------------------
-- BuskDFX numbering
-- ---------------------------------------------------------------
local BUSK_W, BUSK_COLS, BUSK_ROW0, BUSK_STEP, BUSK_GROUPS = 18, 17, 10, 4, 8
local function buskNo(row, col) return BUSK_W * (row - 1) + col end
local function buskRow(g) return BUSK_ROW0 + (g - 1) * BUSK_STEP end

-- in which of Groups 1-8 are these fixtures (master or any part)?
-- Compares selection indexes only. Returns g (or nil) and a text.
local function detectBuskGroup(types, fids)
    local set, hits, names = {}, {}, {}
    local ok = pcall(inBuffer2, function()
        local all, seen = {}, {}
        for _, t in ipairs(types) do
            if not t.all then
                for _, a in ipairs(addressesFor(t, fids)) do
                    if not seen[a] then seen[a] = true; all[#all + 1] = a end
                end
            end
        end
        for i = 1, #all, CHUNK do
            local chunk = {}
            for j = i, math.min(i + CHUNK - 1, #all) do chunk[#chunk + 1] = all[j] end
            Cmd("Fixture " .. table.concat(chunk, " Fixture "))
        end
        local idx, n = SelectionFirst(), 0
        while idx and n < 20000 do set[idx] = true; n = n + 1; idx = SelectionNext(idx) end
        for g = 1, BUSK_GROUPS do
            if groupExists(g) then
                Cmd("ClearSelection")
                Cmd("Group " .. g)
                local c, k = 0, 0
                idx = SelectionFirst()
                while idx and k < 20000 do
                    k = k + 1
                    if set[idx] then c = c + 1 end
                    idx = SelectionNext(idx)
                end
                if c > 0 then
                    hits[#hits + 1] = { g = g, c = c }
                    names[g] = nodeName(DataPool().Groups[g])
                end
            end
        end
    end)
    if not ok then return nil, "BuskDFX: could not read Groups 1-8" end
    if #hits == 0 then return nil, "BuskDFX: these fixtures are in none of Groups 1-8" end
    table.sort(hits, function(a, b) return a.c > b.c end)
    if #hits > 1 and hits[1].c == hits[2].c then
        local l = {}
        for _, h in ipairs(hits) do l[#l + 1] = tostring(h.g) end
        return nil, "BuskDFX: fixtures are in Groups " .. table.concat(l, ", ") .. " - type the one you want"
    end
    local g = hits[1].g
    return g, string.format("BuskDFX: fixtures are in Group %d '%s' -> groups %d / %d / %d ...",
        g, names[g] or "", buskNo(buskRow(g), 1), buskNo(buskRow(g) + 1, 1), buskNo(buskRow(g) + 2, 1))
end

-- ---------------------------------------------------------------
-- normal mode
-- ---------------------------------------------------------------
local function ask(fields)
    return MessageBox(fields)
end

-- first group number after the highest used one, rounded up to x1
local function suggestStart()
    local maxNo = 0
    for _, g in ipairs(safe(function() return DataPool().Groups:Children() end) or {}) do
        local n = tonumber(safe(function() return g.no end)) or tonumber(prop(g, "NO"):match("^%d+")) or 0
        if n > maxNo then maxNo = n end
    end
    if maxNo == 0 then return 1 end
    return (math.floor(maxNo / 10) + 1) * 10 + 1
end

-- v4.6: the fixture IDs a group holds, ascending. An item that is a sub-fixture counts as its fixture.
local function groupFids(g)
    local list, seen = {}, {}
    pcall(inBuffer2, function()
        Cmd("Group " .. g)
        local idx, n = SelectionFirst(), 0
        while idx and n < 20000 do
            n = n + 1
            local h = safe(GetSubfixture, idx)
            local guard = 0
            while h and safe(function() return h:GetClass() end) ~= "Fixture" and guard < 8 do
                guard = guard + 1
                h = safe(function() return h:Parent() end)
            end
            local fid = h and tonumber(safe(function() return h.fid end))
            if fid and not seen[fid] then seen[fid] = true; list[#list + 1] = fid end
            idx = SelectionNext(idx)
        end
    end)
    table.sort(list)
    return list
end

-- v4.6: what to work on. Returns "group", g  |  "range"  |  nil (cancelled)
local function pickTarget(displayHandle)
    local items, byName = {}, {}
    for g = 1, BUSK_GROUPS do
        if groupExists(g) then
            local nm = string.format("G%d  %s", g, nodeName(safe(function() return DataPool().Groups[g] end)))
            items[#items + 1] = nm
            byName[nm] = g
        end
    end
    if #items == 0 then return "range" end
    local RANGE = "Type a fixture range"
    items[#items + 1] = RANGE
    local ok, idx, picked = pcall(function()
        return PopupInput({ title = "InstanceForge - which fixtures?", caller = displayHandle, items = items })
    end)
    if not ok then return "range" end                       -- the list could not be opened: the dialog of before
    local name = picked ~= nil and tostring(picked) or nil
    if not name and type(idx) == "number" and items[idx] then name = items[idx] end
    if not name then return nil end
    if name == RANGE then return "range" end
    if byName[name] then return "group", byName[name] end
    return nil
end

-- manual instances: "1 Thru 20"  or  "Pixel=1 Thru 20 / Edge=1 + 20"
-- one module per "/" ; items joined with + or , ; "a Thru b" or "a-b" ; "2.1 Thru 2.9" ranges the last number
local function parseManual(text, relSet)
    local out = {}
    for seg0 in (text .. "/"):gmatch("(.-)/") do
        local seg = trim(seg0)
        if seg ~= "" then
            local nm, body = seg:match("^(.-)=(.*)$")
            if not nm then nm, body = "", seg end
            nm = trim(nm):gsub('"', "")
            if nm == "" then nm = "Part " .. (#out + 1) end
            local rels, seen = {}, {}
            for item0 in (body:gsub(",", "+") .. "+"):gmatch("(.-)%+") do
                local item = trim(item0)
                if item ~= "" then
                    local a, b = item:lower():match("^([%d%.]+)%s*thru%s*([%d%.]+)$")
                    if not a then a, b = item:match("^([%d%.]+)%s*%-%s*([%d%.]+)$") end
                    if not a then a = item:match("^([%d%.]+)$"); b = a end
                    if not a then return nil, "Cannot read '" .. item .. "'" end
                    local pa, na = a:match("^(.-)(%d+)$")
                    local pb, nb = b:match("^(.-)(%d+)$")
                    if not na or not nb then return nil, "Cannot read '" .. item .. "'" end
                    if pb == "" then pb = pa end
                    if pa ~= pb then return nil, "Different parents in '" .. item .. "'" end
                    na, nb = tonumber(na), tonumber(nb)
                    local step = (nb >= na) and 1 or -1
                    for n = na, nb, step do
                        local rel = pa .. n
                        if not relSet[rel] then return nil, "Instance ." .. rel .. " does not exist in this fixture" end
                        if not seen[rel] then seen[rel] = true; rels[#rels + 1] = rel end
                    end
                end
            end
            if #rels > 0 then out[#out + 1] = { name = nm, rels = rels, cat = 4, manual = true, col = #out + 1 } end
        end
    end
    if #out == 0 then return nil, "No instances given" end
    return out
end

local function runNormal(displayHandle)
    local how, pickG = pickTarget(displayHandle)
    if not how then return end
    local r1
    if how == "range" then
    r1 = ask({
        title = "InstanceForge",
        message = "Fixture range (first fixture decides the type)",
        commands = { { value = 1, name = "Next" }, { value = 0, name = "Cancel" } },
        inputs = {
            { name = "First FID", value = "1", whitefilter = "0123456789" },
            { name = "Last FID",  value = "10", whitefilter = "0123456789" },
        },
        states = {
            { name = "Reset saved names", state = false },
        },
    })
    if not r1 or r1.result ~= 1 then return end
    end
    local ref, refKey, fids, skipped
    local first, last
    if how == "group" then
        ref, refKey, fids, skipped = collectList(groupFids(pickG))
        if not ref then
            MessageBox({ title = "InstanceForge", message = "Group " .. pickG .. " holds no fixtures.\nNothing was created.",
                         commands = { { value = 1, name = "Ok" } } })
            return
        end
    else
        first = tonumber(r1.inputs["First FID"])
        last  = tonumber(r1.inputs["Last FID"])
        if not first or not last then return end
        if last < first then first, last = last, first end
        ref, refKey, fids, skipped = collect(first, last)
        if not ref then
            MessageBox({ title = "InstanceForge", message = "No fixtures in " .. first .. "-" .. last,
                         commands = { { value = 1, name = "Ok" } } })
            return
        end
    end
    first, last = first or fids[1], last or fids[#fids]
    local nodes = walk(ref, "", 1, {})
    local types = detectTypes(nodes)
    for i, t in ipairs(types) do t.col = i end
    local buskG, buskInfo
    if how == "group" then                                  -- chosen, not detected
        buskG = pickG
        buskInfo = string.format("BuskDFX: Group %d '%s' chosen -> groups %d / %d / %d ...", pickG,
            nodeName(safe(function() return DataPool().Groups[pickG] end)),
            buskNo(buskRow(pickG), 1), buskNo(buskRow(pickG) + 1, 1), buskNo(buskRow(pickG) + 2, 1))
    else
        buskG, buskInfo = detectBuskGroup(types, fids)
    end
    local saved = loadNames(refKey)
    if r1 and r1.states and r1.states["Reset saved names"] then
        saved = {}
        saveNames(refKey, {})
    end

    -- dialog 2: one input per type (empty = skip)
    -- (MA3 shows inputs in alphabetical order)
    local inputs = {
        { name = "BuskDFX group", value = "", whitefilter = "12345678" },   -- toolkit: empty by default (numbers from Start Group) ; type 1-8 for BuskDFX numbering
        { name = "Manual instances", value = "" },
        { name = "Prefix",      value = "" },
        { name = "Start Group", value = tostring(suggestStart()), whitefilter = "0123456789" },
    }
    local lines = {}
    for i, t in ipairs(types) do
        local label = string.format("Type %02d", i)
        t.label = label
        inputs[#inputs + 1] = { name = label, value = saved[t.name] or t.name }
        lines[#lines + 1] = string.format("%s  %-16s %3d/fix  %s", label, t.name, #t.rels, describe(t, ref))
    end
    local r2 = ask({
        title = "InstanceForge - " .. refKey,
        message = string.format("%d fixtures%s\nEdit names, empty = skip\n"
            .. "Manual instances (instead of the types, Master stays): 1 Thru 20   or   Pix=1 Thru 20 / Edge=1 + 20\n"
            .. "%s\nBuskDFX group 1-8 = numbers of BuskDFX, empty = from Start Group\n\n%s",
            #fids, (skipped > 0) and (", " .. skipped .. " of another type skipped") or "",
            buskInfo, table.concat(lines, "\n")),
        commands = { { value = 1, name = "Create" }, { value = 0, name = "Cancel" } },
        inputs = inputs,
        states = {
            { name = "Also linear groups (one line)", state = buskG ~= nil },
            { name = "Template groups (first fixture)", state = true },
            { name = "Reset saved names (then run again)", state = false },
        },
    })
    if not r2 or r2.result ~= 1 then return end
    if r2.states["Reset saved names (then run again)"] then
        saveNames(refKey, {})
        MessageBox({ title = "InstanceForge", message = "Saved names of this fixture type were reset.\nNothing was created. Run again.",
                     commands = { { value = 1, name = "Ok" } } })
        return
    end
    local manualText = trim(r2.inputs["Manual instances"] or "")
    local manual = manualText ~= ""
    if manual then
        local relSet = {}
        for _, nd in ipairs(nodes) do relSet[nd.rel] = true end
        local mt, err = parseManual(manualText, relSet)
        if not mt then
            MessageBox({ title = "InstanceForge", message = "Manual instances: " .. tostring(err) .. "\nNothing was created.",
                         commands = { { value = 1, name = "Ok" } } })
            return
        end
        -- the Master (the fixture itself) keeps its column, manual modules follow it
        local keep = {}
        for _, t in ipairs(types) do if t.cat == 0 then keep[#keep + 1] = t end end
        for _, t in ipairs(mt) do keep[#keep + 1] = t end
        for i, t in ipairs(keep) do t.col = i end
        types = keep
    end

    local matrixOn = true
    local linearOn = r2.states["Also linear groups (one line)"] and true or false
    local prefix = trim(r2.inputs["Prefix"]):gsub('"', "")
    local pre    = (prefix ~= "") and (prefix .. " ") or ""
    local busk   = tonumber(trim(r2.inputs["BuskDFX group"]))
    if busk and (busk < 1 or busk > BUSK_GROUPS) then busk = nil end
    if busk and prefix == "" then
      local gh = safe(function() return DataPool().Groups[busk] end)
      local gn = gh and nodeName(gh):gsub('"', "") or ""
      if gn ~= "" then prefix = gn; pre = gn .. " " end
    end
    if busk and #types > BUSK_COLS then
        MessageBox({ title = "InstanceForge",
                     message = string.format("This fixture has %d instance types.\nA BuskDFX row holds %d."
                         .. "\nNothing was created.\n\nLeave 'BuskDFX group' empty to number from Start Group.",
                         #types, BUSK_COLS),
                     commands = { { value = 1, name = "Ok" } } })
        return
    end

    -- three blocks, each with its own start
    local blocks, newSaved = {}, {}
    local main = { title = "Types", start = tonumber(r2.inputs["Start Group"]) or suggestStart(), list = {} }
    for _, t in ipairs(types) do
        local nm = t.manual and t.name or trim(r2.inputs[t.label])
        if not t.manual then newSaved[t.name] = nm end
        if nm ~= "" then
            main.list[#main.list + 1] = { name = pre .. nm, rows = rowsFor(t, fids), t = t }
        end
    end
    blocks[#blocks + 1] = main
    -- linear groups: the matrix groups again as one line, one empty number before
    if linearOn then
        local b = { title = "Linear", gap = 1, list = {} }
        for _, g in ipairs(main.list) do
            if useMatrix(g.rows, true) then
                b.list[#b.list + 1] = { name = g.name .. " Line", rows = g.rows, row = true, t = g.t }
            end
        end
        blocks[#blocks + 1] = b
    end
    -- template groups: first fixture only, for types with more than one instance
    if r2.states["Template groups (first fixture)"] then
        local b = { title = "Templates", gap = 1, list = {} }
        local cands = {}
        for _, g in ipairs(main.list) do cands[#cands + 1] = { name = g.name, row1 = g.rows[1], t = g.t } end
        for _, g in ipairs(templateList(cands)) do
            b.list[#b.list + 1] = { name = g.name .. " Template", rows = { g.row1 }, row = true, t = g.t }
        end
        blocks[#blocks + 1] = b
    end

    -- resolve the group number of every group, check overlaps and used groups
    local total, used, nextFree, summary, taken, clash = 0, 0, nil, {}, {}, false
    for bi, b in ipairs(blocks) do
        if #b.list > 0 then
            if busk then
                -- column = instance type; a "Unit" template has no type of
                -- its own: first free column after the types
                local row, colUsed = buskRow(busk) + bi - 1, {}
                if b.title == "Templates" then row = buskRow(busk) + 2 end
                if b.title == "Linear" then row = buskRow(busk) + 1 end
                for _, g in ipairs(b.list) do
                    if g.t then g.num = buskNo(row, g.t.col); colUsed[g.t.col] = true end
                end
                for _, g in ipairs(b.list) do
                    if not g.num then
                        local c = #types + 1
                        while c <= BUSK_COLS and colUsed[c] do c = c + 1 end
                        if c > BUSK_COLS then
                            c = 1
                            while c <= BUSK_COLS and colUsed[c] do c = c + 1 end
                        end
                        if c > BUSK_COLS then clash = true; c = BUSK_COLS end
                        colUsed[c] = true
                        g.num = buskNo(row, c)
                    end
                end
            else
                b.start = b.start or ((nextFree or 1) + (b.gap or 0))
                for i, g in ipairs(b.list) do g.num = b.start + i - 1 end
            end
            b.first, b.last = b.list[1].num, b.list[1].num
            for _, g in ipairs(b.list) do
                if g.num < b.first then b.first = g.num end
                if g.num > b.last then b.last = g.num end
                if taken[g.num] then clash = true end
                taken[g.num] = true
                if groupExists(g.num) then used = used + 1 end
            end
            nextFree = b.last + 1
            total = total + #b.list
            summary[#summary + 1] = string.format("%-13s %3d groups   %d thru %d", b.title, #b.list, b.first, b.last)
        end
    end
    if total == 0 then return end
    if clash then
        MessageBox({ title = "InstanceForge",
                     message = "The group ranges overlap:\n\n" .. table.concat(summary, "\n"),
                     commands = { { value = 1, name = "Ok" } } })
        return
    end
    local ok = MessageBox({
        title = "InstanceForge",
        message = string.format("Create %d groups:\n\n%s%s\n\nYour selection is kept.",
            total, table.concat(summary, "\n"),
            (used > 0) and ("\n\n" .. used .. " existing groups will be OVERWRITTEN") or ""),
        commands = { { value = 1, name = "Ok" }, { value = 0, name = "Cancel" } },
    })
    if not ok or ok.result ~= 1 then return end

    local undo = CreateUndo("InstanceForge")
    local prog = progStart("InstanceForge", total)
    inBuffer2(function()
        for _, b in ipairs(blocks) do
            for i, g in ipairs(b.list) do
                g.addrs = flatten(g.rows)
                g.matrix = (not g.row) and useMatrix(g.rows, matrixOn)
                storeGroup(g.num, g.name, g.rows, undo, g.matrix)
                breathe()
                g.got, g.dims = verify(g.num)
                progInc(prog)
            end
        end
    end)
    progStop(prog)
    CloseUndo(undo)
    if not manual then saveNames(refKey, newSaved) end

    -- report: IF3_report.txt in the gma3_library folder
    local rep, bad = {}, 0
    local function r(fmt, ...) rep[#rep + 1] = string.format(fmt, ...) end
    local bd = safe(BuildDetails) or {}
    r("")
    r("===== InstanceForge 4.7 report  %s  (%s %s) =====", tostring(safe(os.date, "%Y-%m-%d %H:%M:%S")),
        tostring(bd.BigVersion), tostring(bd.HostType))
    r("Numbering: %s", busk and string.format("BuskDFX group %d (rows %d-%d)   %s", busk, buskRow(busk),
        buskRow(busk) + 2, tostring(buskInfo)) or ("free, from Start Group   " .. tostring(buskInfo)))
    r("Range %d-%d   type: %s   fixtures: %d   skipped: %d", first, last, refKey, #fids, skipped)
    r("Prefix: '%s'   linear: %s   templates: %s   reset names: %s", prefix, tostring(linearOn),
        tostring(r2.states["Template groups (first fixture)"] or false),
        tostring(r1 and r1.states and r1.states["Reset saved names"] or false))
    r("")
    r("--- tree of fixture %d ---", fids[1])
    for _, nd in ipairs(nodes) do
        r("%s.%-8s %s", string.rep("  ", nd.depth - 1), nd.rel, nd.name)
    end
    r("")
    r("--- types: detected -> used ---")
    for _, t in ipairs(types) do
        local nm = t.manual and t.name or trim(r2.inputs[t.label])
        r("%s  %-6s %-18s -> %-18s %3d/fix  %s %s", t.label or "Manual", CAT_TITLE[t.cat], t.name,
            (nm ~= "") and nm or "(skipped)", #t.rels, t.manual and "manual instances" or describe(t, ref),
            (saved[t.name] and saved[t.name] ~= t.name) and ("[saved: " .. saved[t.name] .. "]") or "")
    end
    for _, b in ipairs(blocks) do
        if #b.list > 0 then
            r("")
            r("--- %s: groups %d thru %d ---", b.title, b.first, b.last)
            for i, g in ipairs(b.list) do
                local num = g.num
                local shown = {}
                for j = 1, math.min(#g.addrs, 6) do shown[#shown + 1] = g.addrs[j] end
                local want = g.matrix and (#g.rows[1] .. "x" .. #g.rows) or (#g.addrs .. "x1")
                if g.got ~= #g.addrs or g.dims ~= want then bad = bad + 1 end
                r("Group %d  %-24s expected %4d %-7s selected %4d %-7s %s  | %s%s", num, g.name,
                    #g.addrs, want, g.got or -1, tostring(g.dims),
                    (g.got == #g.addrs and g.dims == want) and "OK" or "CHECK",
                    table.concat(shown, " "), (#g.addrs > 6) and " ..." or "")
            end
        end
    end
    r("")
    r("RESULT: %d groups created, %d problems", total, bad)
    local path = writeReport("IF3_report.txt", rep, true)
    Printf("InstanceForge: created %d groups, %d problems%s", total, bad,
        path and ("  report: " .. path) or "")
end

local function main(displayHandle, argument)
    if FORCE_TEST or tostring(argument or ""):lower() == "test" then
        runTest()
    else
        runNormal(displayHandle)
    end
end

return main
