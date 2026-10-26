-- ============================================================
--  GridForge  v1.0  for grandMA3 (tested on 2.5.0.3)
--  Selection Grid tools - works on the CURRENT selection
-- ------------------------------------------------------------
--  Concept, design & testing : Amir Nehmad
--  Code                      : Claude (Anthropic), with Amir
--  Released: September 2026 - free to use and share
-- ------------------------------------------------------------
--  Tools
--    Matrix    columns, spacing X/Y, extra gap every N,
--              snake, fill by rows or columns
--    Diagonal  Line / Zigzag / Blocks, 4 directions,
--              start at first or last, step X/Y
--    Ring      circle, radius auto or typed, start side, CW/CCW
--              several rings: "Ring sizes" e.g. 1,6,12 (centre out)
--    Mirror    two runs: 1) record the placed half
--                        2) select the other half, run again
--    Sync      rebuild a combined group from its part groups: every
--              part keeps its place in the combined group, but gets
--              its new inner layout (parts are remembered)
--    GridStore store the current selection's grid to the fixture
--              type (also offered after Copy "Stack on shape")
--    Reset     set Grid Auto back to Auto on every geometry of the
--              fixture types in the selection (undoes GridStore)
--    Copy      two runs: 1) record a shape
--                        2) select one or more groups of the same
--                           size, run again -> each gets the shape
--  Matrix / Diagonal / Ring: "Only group N" arranges only the fixtures of
--  group N that are in the selection; the rest stays in place.
--  The group can keep its place, go right of / below the rest, or
--  "Free": keep its place, moved right until nothing overlaps.
--  Every tool keeps the selection order, rebuilds the selection
--  with the grid cursor ("Grid x/y/z" + fixture), reads it back
--  and checks every position. Optional: store to a group.
--  Log: gma3_library\GF_report.txt - every run is ADDED at the
--  end with date/time (also Mirror steps, cancels, errors).
--  Delete the file to start a fresh log.
--
--  Arguments (for quick buttons):
--    Plugin "GridForge" "matrix" | "diagonal" | "ring" | "mirror"
--                       | "copy" | "sync" | "gridstore" | "reset" | "test"
--  Test mode (argument "test" or the GF_Test plugin) uses
--  fixtures TEST_FIRST..TEST_LAST in selection buffer 2 and
--  writes gma3_library\GF_test.txt. Your selection is kept.
-- ============================================================

local pluginName, componentName, signalTable, myHandle = select(1, ...)

local VERSION    = "1.0"
local FORCE_TEST = false
local TEST_FIRST, TEST_LAST = 1, 10
local MIRROR_VAR = "GF_MIRROR"
local COPY_VAR   = "GF_COPY"
local SYNC_VAR   = "GF_SYNC_"   -- + group number: remembered part groups

-- ---------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------
local function safe(f, ...)
    local ok, v = pcall(f, ...)
    if ok then return v end
    return nil
end
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function num(s, def)
    local v = tonumber(trim(s))
    if v == nil then return def end
    return math.floor(v)
end
local function breathe(t) pcall(coroutine.yield, t or 0.02) end

local function progStart(title, n)
    local h = safe(StartProgress, title)
    if h then safe(SetProgressRange, h, 1, math.max(n, 1)) end
    return h
end
local function progInc(h) if h then safe(IncProgress, h, 1) end end
local function progStop(h) if h then safe(StopProgress, h) end end

local function libPath(fileName)
    local dir = safe(function() return GetPath(Enums.PathType.Library) end)
        or "C:\\ProgramData\\MALightingTechnology\\gma3_library"
    local sep = dir:find("\\") and "\\" or "/"
    return dir .. sep .. fileName
end
local function writeFile(fileName, lines)
    local path = libPath(fileName)
    local f = io.open(path, "w")
    if not f then return nil end
    f:write(table.concat(lines, "\n"), "\n")
    f:close()
    return path
end

-- append to the running log GF_report.txt
local function logRun(lines)
    local path = libPath("GF_report.txt")
    local f = io.open(path, "a")
    if not f then return end
    local stamp = tostring(safe(function() return os.date("%Y-%m-%d %H:%M:%S") end) or "")
    f:write("\n[" .. stamp .. "]  ", table.concat(lines, "\n"), "\n")
    f:close()
end
local function logLine(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    logRun({ "GridForge " .. VERSION .. "  " .. (ok and s or tostring(fmt)) })
end

local function msg(title, text)
    MessageBox({ title = title, message = text, commands = { { value = 1, name = "Ok" } } })
end

-- ---------------------------------------------------------------
-- selection  <->  list of { addr, x, y, z }
-- ---------------------------------------------------------------
local function readSelection()
    local list = {}
    local idx, x, y, z = SelectionFirst()
    while idx and #list < 10000 do
        local h = GetSubfixture(idx)
        local a = h and safe(function() return h:ToAddr() end)
        if a then list[#list + 1] = { addr = tostring(a), x = x or 0, y = y or 0, z = z or 0 } end
        idx, x, y, z = SelectionNext(idx)
    end
    return list
end

local function bounds(list)
    local b = { minX = math.huge, maxX = -math.huge, minY = math.huge, maxY = -math.huge }
    for _, e in ipairs(list) do
        if e.x < b.minX then b.minX = e.x end
        if e.x > b.maxX then b.maxX = e.x end
        if e.y < b.minY then b.minY = e.y end
        if e.y > b.maxY then b.maxY = e.y end
    end
    return b
end

local function shift(list, dx, dy)
    for _, e in ipairs(list) do e.nx = e.nx + dx; e.ny = e.ny + dy end
end

-- new positions (nx, ny): top-left goes to "to" {x, y},
-- or (to = nil) stays where the top-left of the old layout was
local function anchor(list, orig, to)
    local minX, minY = math.huge, math.huge
    for _, e in ipairs(list) do
        minX = math.min(minX, e.nx); minY = math.min(minY, e.ny)
    end
    local tx, ty = orig and orig.minX or 0, orig and orig.minY or 0
    if to then tx, ty = to.x, to.y end
    shift(list, tx - minX, ty - minY)
end

-- "Grid x/y/z" syntax for negative numbers: found once per run
local gridFmt = function(x, y, z) return "Grid " .. x .. "/" .. y .. "/" .. z end
local negativeOk = nil

local function probeNegative(addr, rep)
    if negativeOk ~= nil then return negativeOk end
    local tries = {
        function(x, y, z) return "Grid " .. x .. "/" .. y .. "/" .. z end,
        function(x, y, z) return 'Grid "' .. x .. "/" .. y .. "/" .. z .. '"' end,
    }
    negativeOk = false
    -- runs in the current buffer: it is cleared and rebuilt right after
    for i, f in ipairs(tries) do
        Cmd("ClearSelection")
        Cmd(f(-3, -2, 0)); Cmd(addr)
        local _, x, y = SelectionFirst()
        rep[#rep + 1] = string.format("negative probe %d: '%s' -> %s/%s", i, f(-3, -2, 0), tostring(x), tostring(y))
        if x == -3 and y == -2 then gridFmt = f; negativeOk = true break end
    end
    Cmd("ClearSelection")
    return negativeOk
end

-- rebuild the current buffer from list (uses nx, ny), then verify
local function place(list, undo, rep)
    local b = { minX = math.huge, minY = math.huge }
    for _, e in ipairs(list) do b.minX = math.min(b.minX, e.nx); b.minY = math.min(b.minY, e.ny) end
    if (b.minX < 0 or b.minY < 0) and not probeNegative(list[1].addr, rep) then
        -- no negative positions: move everything to 0/0
        shift(list, math.max(0, -b.minX), math.max(0, -b.minY))
        rep[#rep + 1] = "negative positions not accepted -> shifted to 0/0"
    end
    -- whole cells only (no "0.0" in the command line)
    for _, e in ipairs(list) do
        e.nx, e.ny = math.floor(e.nx + 0.5), math.floor(e.ny + 0.5)
        e.z = math.floor((e.z or 0) + 0.5)
    end
    local prog = (#list > 60) and progStart("GridForge", #list) or nil
    Cmd("ClearSelection", undo)
    for i, e in ipairs(list) do
        Cmd(gridFmt(e.nx, e.ny, e.z), undo)
        Cmd(e.addr, undo)
        if i % 20 == 0 then breathe(); progInc(prog) end
    end
    progStop(prog)
    -- verify
    local want = {}
    for _, e in ipairs(list) do want[e.addr] = e end
    local got, bad, n = readSelection(), 0, 0
    for _, g in ipairs(got) do
        n = n + 1
        local w = want[g.addr]
        if not w or w.nx ~= g.x or w.ny ~= g.y then
            bad = bad + 1
            if bad <= 10 then
                rep[#rep + 1] = string.format("  CHECK %-22s want %s/%s  got %d/%d", g.addr,
                    w and tostring(w.nx) or "?", w and tostring(w.ny) or "?", g.x, g.y)
            end
        end
    end
    if n ~= #list then bad = bad + math.abs(#list - n) end
    return bad, n
end

local function storeTo(groupNo, name, undo)
    if not groupNo then return end
    Cmd("Store Group " .. groupNo .. " /Overwrite", undo)
    if name ~= "" then Cmd('Label Group ' .. groupNo .. ' "' .. name:gsub('"', "") .. '"', undo) end
end

local function dumpList(rep, list, max)
    for i = 1, math.min(#list, max or 40) do
        local e = list[i]
        rep[#rep + 1] = string.format("  %-24s %4d/%-4d -> %4d/%-4d", e.addr, e.x, e.y, e.nx, e.ny)
    end
    if #list > (max or 40) then rep[#rep + 1] = string.format("  ... %d more", #list - (max or 40)) end
end

-- ---------------------------------------------------------------
-- layouts (pure: set nx, ny on every entry)
-- ---------------------------------------------------------------
-- p = { cols, sx, sy, gapEvery, gapSize, snake, byColumns, start0, to }
local function layoutMatrix(list, p)
    local orig = bounds(list)
    local cols = math.max(1, p.cols)
    local rows = math.ceil(#list / cols)
    for i, e in ipairs(list) do
        local k = i - 1
        local c, r
        if p.byColumns then
            -- fill down the columns: the number is ROWS (fixtures per column)
            local perCol = cols
            c, r = math.floor(k / perCol), k % perCol
            if p.snake and c % 2 == 1 then r = perCol - 1 - r end
        else
            r, c = math.floor(k / cols), k % cols
            if p.snake and r % 2 == 1 then c = cols - 1 - c end
        end
        local gx = (p.gapEvery > 0) and math.floor(c / p.gapEvery) * p.gapSize or 0
        e.nx = c * p.sx + gx
        e.ny = r * p.sy
    end
    anchor(list, orig, p.to)
end

-- p = { dir = "DR"|"UR"|"DL"|"UL", fromLast, sx, sy, start0, to,
--       shape = "Line"|"Zigzag"|"Blocks", height, block, tall }
--   Zigzag: goes "height" rows up/down, then turns back
--   Blocks: "block" fixtures side by side (tall = on top of each
--           other), every next block one diagonal step further
local function layoutDiagonal(list, p)
    local orig = bounds(list)
    local gx = (p.dir == "DR" or p.dir == "UR") and 1 or -1
    local gy = (p.dir == "DR" or p.dir == "DL") and 1 or -1
    local n = #list
    local shape = p.shape or "Line"
    for i, e in ipairs(list) do
        local k = p.fromLast and (n - i) or (i - 1)
        local x, y
        if shape == "Zigzag" then
            local h = math.max(2, p.height or 2)
            local period = 2 * (h - 1)
            local ph = k % period
            local level = (ph <= h - 1) and ph or (period - ph)
            x, y = k * p.sx, level * p.sy
        elseif shape == "Blocks" then
            local bs = math.max(1, p.block or 1)
            local b, j = math.floor(k / bs), k % bs
            -- overlap: the next block starts that many cells back
            local ov = math.min(math.max(0, p.overlap or 0), bs - 1)
            if p.tall then
                x, y = b * p.sx, b * (bs - 1 + p.sy - ov) + j
            else
                x, y = b * (bs - 1 + p.sx - ov) + j, b * p.sy
            end
        else
            x, y = k * p.sx, k * p.sy
        end
        e.nx, e.ny = x * gx, y * gy
    end
    anchor(list, orig, p.to)
end

-- ring: p = { radius (0 = auto), start = "Top"|"Right"|"Bottom"|"Left", ccw, to }
-- auto radius: smallest radius where no two fixtures share a cell
local START_ANGLE = { Top = -90, Right = 0, Bottom = 90, Left = 180 }
local function ringPoints(n, r, startDeg, ccw)
    local pts, used, dup = {}, {}, false
    for i = 0, n - 1 do
        local a = math.rad(startDeg + (ccw and -1 or 1) * 360 * i / n)
        local x = math.floor(r * math.cos(a) + 0.5)
        local y = math.floor(r * math.sin(a) + 0.5)
        local key = x .. "/" .. y
        if used[key] then dup = true end
        used[key] = true
        pts[#pts + 1] = { x, y }
    end
    return pts, dup
end
-- p.sizes = { 1, 6, 12 } -> centre point, ring of 6, ring of 12
-- (inside out). Empty = one ring with all fixtures.
-- p.fromOutside: the first fixtures go to the outer ring
-- p.gap: minimum radius step between rings
local function layoutRing(list, p)
    local orig = bounds(list)
    local n = #list
    local startDeg = START_ANGLE[p.start or "Top"] or -90
    -- fit the ring sizes to the fixture count
    local fitted, sum = {}, 0
    for _, k in ipairs(p.sizes or {}) do
        if sum < n and k > 0 then
            local take = math.min(k, n - sum)
            fitted[#fitted + 1] = take; sum = sum + take
        end
    end
    if sum < n then fitted[#fitted + 1] = n - sum end
    p.fitted = fitted
    local used, rings, prevR, radii = {}, {}, -1, {}
    for ri, size in ipairs(fitted) do
        local pts, r
        if size == 1 and ri == 1 then
            r, pts = 0, { { 0, 0 } }
        else
            r = (#fitted == 1 and (p.radius or 0) > 0) and p.radius or math.max(1, prevR + (p.gap or 1))
            while true do
                local dup
                pts, dup = ringPoints(size, r, startDeg, p.ccw)
                local hit = false
                for _, pt in ipairs(pts) do if used[pt[1] .. "/" .. pt[2]] then hit = true break end end
                if not dup and not hit then break end
                if (#fitted == 1 and (p.radius or 0) > 0) or r > 200 then break end   -- typed radius: keep it
                r = r + 1
            end
        end
        for _, pt in ipairs(pts) do used[pt[1] .. "/" .. pt[2]] = true end
        rings[ri] = pts
        radii[#radii + 1] = r
        prevR = r
    end
    p.usedRadius = radii[#radii]
    p.radii = radii
    -- hand out the fixtures ring by ring
    local k = 1
    local first, last, step = 1, #rings, 1
    if p.fromOutside then first, last, step = #rings, 1, -1 end
    for ri = first, last, step do
        for _, pt in ipairs(rings[ri]) do
            local e = list[k]; k = k + 1
            if e then e.nx, e.ny = pt[1], pt[2] end
        end
    end
    anchor(list, orig, p.to)
end

-- mirror: src keeps its place, tgt gets mirrored positions of src
-- p = { axis = "X"|"Y", gap, innerFirst, start0 }
-- rows of the source (same Y for axis X) are matched in order with
-- consecutive chunks of the target selection
local function layoutMirror(src, tgt, p)
    local A, B = (p.axis == "X") and "x" or "y", (p.axis == "X") and "y" or "x"
    local maxA = -math.huge
    for _, e in ipairs(src) do if e[A] > maxA then maxA = e[A] end end
    local line = 2 * maxA + p.gap          -- a' = line - a
    -- source rows in order of first appearance
    local rows, byKey = {}, {}
    for _, e in ipairs(src) do
        local k = e[B]
        if not byKey[k] then byKey[k] = {}; rows[#rows + 1] = byKey[k] end
        table.insert(byKey[k], e)
    end
    local t = 1
    for _, row in ipairs(rows) do
        table.sort(row, function(a, b)
            if p.innerFirst then return a[A] > b[A] end
            return a[A] < b[A]
        end)
        for _, s in ipairs(row) do
            local e = tgt[t]; t = t + 1
            if not e then break end
            local na = line - s[A]
            if A == "x" then e.nx, e.ny = na, s.y else e.nx, e.ny = s.x, na end
            e.z = s.z
        end
    end
    for _, e in ipairs(src) do e.nx, e.ny = e.x, e.y end
    local all = {}
    for _, e in ipairs(src) do all[#all + 1] = e end
    for _, e in ipairs(tgt) do all[#all + 1] = e end
    if p.start0 then anchor(all, nil, { x = 0, y = 0 }) end
    return all
end

-- copy: src = recorded shape (positions), tgt = selection without
-- the recorded fixtures, cut into chunks of #src in selection order.
-- p = { place = "Keep"|"Row"|"Column"|"Grid", perRow, gap }
--   Keep   = each chunk starts at its own current top-left
--   Row    = chunks side by side, right of the recorded shape
--   Column = chunks under each other, below the recorded shape
--   Grid   = the recorded shape is cell 1, copies fill "perRow" per row
--   Stack  = every copy exactly on top of the recorded shape (same
--            start cell) - e.g. every yoke's pixels from the same 0/0
--            before GridStore
local function layoutCopy(src, chunks, p)
    local sb = bounds(src)
    local w, h = sb.maxX - sb.minX + 1, sb.maxY - sb.minY + 1
    local g = math.max(0, p.gap or 1)
    for ci, chunk in ipairs(chunks) do
        local ox, oy
        if p.place == "Row" then
            ox, oy = sb.minX + ci * (w + g), sb.minY
        elseif p.place == "Column" then
            ox, oy = sb.minX, sb.minY + ci * (h + g)
        elseif p.place == "Stack" then
            ox, oy = sb.minX, sb.minY
        elseif p.place == "Grid" then
            local per = math.max(1, p.perRow or 5)
            ox, oy = sb.minX + (ci % per) * (w + g), sb.minY + math.floor(ci / per) * (h + g)
        else
            local cb = bounds(chunk)
            ox, oy = cb.minX, cb.minY
        end
        for i, e in ipairs(chunk) do
            local s0 = src[i]
            e.nx, e.ny, e.z = ox + (s0.x - sb.minX), oy + (s0.y - sb.minY), s0.z
        end
    end
end

-- ---------------------------------------------------------------
-- mirror memory (GlobalVars)
-- ---------------------------------------------------------------
local function saveRec(var, list)
    local t = {}
    for _, e in ipairs(list) do t[#t + 1] = e.addr .. "|" .. e.x .. "|" .. e.y .. "|" .. e.z end
    safe(function() SetVar(GlobalVars(), var, table.concat(t, ";")) end)
end
local function saveMirror(list) saveRec(MIRROR_VAR, list) end
local function loadRec(var)
    local s = safe(function() return GetVar(GlobalVars(), var) end)
    local list = {}
    if not s or s == "" then return list end
    for item in tostring(s):gmatch("[^;]+") do
        local a, x, y, z = item:match("^(.-)|(%-?%d+)|(%-?%d+)|(%-?%d+)$")
        if a then list[#list + 1] = { addr = a, x = tonumber(x), y = tonumber(y), z = tonumber(z) } end
    end
    return list
end
local function loadMirror() return loadRec(MIRROR_VAR) end
local function clearRec(var) safe(function() SetVar(GlobalVars(), var, "") end) end
local function clearMirror() clearRec(MIRROR_VAR) end

-- ---------------------------------------------------------------
-- dialogs
-- (MA3 sorts inputs alphabetically -> numbered names)
-- ---------------------------------------------------------------
local function storeInputs(inputs)
    inputs[#inputs + 1] = { name = "9 Store Group (empty = no)", value = "", whitefilter = "0123456789", vkPlugin = "NumericInput" }
    inputs[#inputs + 1] = { name = "9b Group name", value = "" }
end
local function storeFrom(r)
    return num(r.inputs["9 Store Group (empty = no)"], nil), trim(r.inputs["9b Group name"])
end

local function finish(title, list, params, undo, gNo, gName, overlapOk)
    local rep = {}
    rep[#rep + 1] = string.format("GridForge %s  %s", VERSION, title)
    rep[#rep + 1] = params
    local bad, n = place(list, undo, rep)
    storeTo(gNo, gName, undo)
    local cells, overlap = {}, 0
    for _, e in ipairs(list) do
        local key = e.nx .. "/" .. e.ny .. "/" .. (e.z or 0)
        if cells[key] then overlap = overlap + 1 end
        cells[key] = true
    end
    rep[#rep + 1] = string.format("%d fixtures, placed %d, problems %d%s%s", #list, n, bad,
        gNo and ("   stored to group " .. gNo) or "",
        (overlap > 0 and not overlapOk) and ("   WARNING: " .. overlap .. " fixtures on a cell that is already used") or "")
    dumpList(rep, list)
    logRun(rep)
    Printf("GridForge %s: %d fixtures, %d problems%s", title, #list, bad, gNo and (", group " .. gNo) or "")
    if overlap > 0 and not overlapOk then
        msg("GridForge - " .. title, overlap .. " fixtures landed on a cell that is already used.\n"
            .. "Oops to undo, or try Right of rest / Below rest.")
    end
    return bad
end

local function needSelection(title)
    local list = readSelection()
    if #list == 0 then
        logLine("%s: nothing selected", title)
        msg("GridForge - " .. title, "Nothing selected.\nSelect fixtures first.")
        return nil
    end
    return list
end

-- "Only group": read the group in buffer 2 (your selection is kept)
local function readGroup(no)
    Cmd("Selection 2"); Cmd("ClearSelection"); Cmd("Group " .. no)
    local g = readSelection()
    Cmd("ClearSelection"); Cmd("Selection 1")
    local order = {}
    for _, e in ipairs(g) do order[#order + 1] = e.addr end
    return order
end

local PLACES = { "Keep", "Right", "Below", "Free" }
-- lay out all, or only the fixtures in "order" (rest stays in place)
-- returns number of arranged fixtures (0 = none of the group selected)
local function arrange(all, order, layoutFn, p, place)
    if not order then
        if p.start0 then p.to = { x = 0, y = 0 } end
        layoutFn(all, p)
        return #all
    end
    local byAddr, sub, inSub, rest = {}, {}, {}, {}
    for _, e in ipairs(all) do byAddr[e.addr] = e end
    for _, a in ipairs(order) do
        local e = byAddr[a]
        if e and not inSub[a] then sub[#sub + 1] = e; inSub[a] = true end
    end
    if #sub == 0 then return 0 end
    for _, e in ipairs(all) do
        if not inSub[e.addr] then e.nx, e.ny = e.x, e.y; rest[#rest + 1] = e end
    end
    if #rest > 0 and place == "Right" then
        local rb = bounds(rest); p.to = { x = rb.maxX + 2, y = rb.minY }
    elseif #rest > 0 and place == "Below" then
        local rb = bounds(rest); p.to = { x = rb.minX, y = rb.maxY + 2 }
    end
    layoutFn(sub, p)
    if place == "Free" and #rest > 0 then
        -- move right until no cell of the group is used by the rest
        local used = {}
        for _, e in ipairs(rest) do used[e.nx .. "/" .. e.ny] = true end
        for step = 0, 1000 do
            local hit = false
            for _, e in ipairs(sub) do
                if used[(e.nx + step) .. "/" .. e.ny] then hit = true break end
            end
            if not hit then
                if step > 0 then shift(sub, step, 0) end
                p.freeShift = step
                break
            end
        end
    end
    return #sub
end

local function groupInputs(inputs, selectors)
    inputs[#inputs + 1] = { name = "8 Only group (empty = all)", value = "", whitefilter = "0123456789", vkPlugin = "NumericInput" }
    selectors[#selectors + 1] = { name = "Only group: place", selectedValue = 1, type = 1,
        values = { ["Keep"] = 1, ["Right of rest"] = 2, ["Below rest"] = 3, ["Free space"] = 4 } }
end
local GROUP_HELP = "\nOnly group: arrange only that group, the rest stays\n"
    .. "   Keep = where it is now, Right of / Below rest = next to the rest\n"
    .. "   Free space = where it is now, moved right until nothing overlaps"

-- returns order (or nil = all), groupNo, place ; false if the group is missing
local function groupFrom(r, list, title)
    local only = num(r.inputs["8 Only group (empty = all)"], nil)
    local place = PLACES[r.selectors["Only group: place"] or 1] or "Keep"
    if not only then return nil, nil, place end
    local order = readGroup(only)
    if #order == 0 then
        logLine("%s: group %d is empty or does not exist", title, only)
        msg("GridForge - " .. title, "Group " .. only .. " is empty or does not exist.")
        return false
    end
    return order, only, place
end

local function runMatrix()
    local list = needSelection("Matrix")
    if not list then return end
    local b = bounds(list)
    local firstRow = 0
    for _, e in ipairs(list) do if e.y == b.minY then firstRow = firstRow + 1 end end
    local inputs = {
        { name = "1 Columns / Rows",        value = tostring(firstRow), whitefilter = "0123456789", vkPlugin = "NumericInput" },
        { name = "2 Space X",               value = "1", whitefilter = "0123456789", vkPlugin = "NumericInput" },
        { name = "3 Space Y",               value = "1", whitefilter = "0123456789", vkPlugin = "NumericInput" },
        { name = "4 Extra gap every N col", value = "0", whitefilter = "0123456789", vkPlugin = "NumericInput" },
        { name = "5 Extra gap size",        value = "1", whitefilter = "0123456789", vkPlugin = "NumericInput" },
    }
    local selectors = {}
    groupInputs(inputs, selectors)
    storeInputs(inputs)
    local r = MessageBox({
        title = "GridForge - Matrix",
        message = string.format("%d fixtures selected (selection order)\n"
            .. "Columns / Rows: fixtures per row (per column with Fill by columns)\n"
            .. "Space: 1 = next to each other, 2 = one empty cell between\n"
            .. "Extra gap: an additional space every N columns (0 = off)\n"
            .. "Snake: every 2nd line reversed (needs 2+ lines)\n"
            .. "Start at 0: top-left of the result at 0/0 (all fixtures only)" .. GROUP_HELP, #list),
        commands = { { value = 1, name = "Apply" }, { value = 0, name = "Cancel" } },
        inputs = inputs,
        selectors = selectors,
        states = {
            { name = "Snake", state = false },
            { name = "Fill by columns", state = false },
            { name = "Start at 0", state = false },
        },
    })
    if not r or r.result ~= 1 then logLine("%s: cancelled (%d selected)", "Matrix", #list) return end
    local p = {
        cols = math.max(1, num(r.inputs["1 Columns / Rows"], firstRow)),
        sx = math.max(1, num(r.inputs["2 Space X"], 1)),
        sy = math.max(1, num(r.inputs["3 Space Y"], 1)),
        gapEvery = num(r.inputs["4 Extra gap every N col"], 0),
        gapSize = num(r.inputs["5 Extra gap size"], 0),
        snake = r.states["Snake"] and true or false,
        byColumns = r.states["Fill by columns"] and true or false,
        start0 = r.states["Start at 0"] and true or false,
    }
    local order, only, place = groupFrom(r, list, "Matrix")
    if order == false then return end
    local n = arrange(list, order, layoutMatrix, p, place)
    if n == 0 then
        logLine("Matrix: none of group %d is in the selection", only)
        msg("GridForge - Matrix", "None of the fixtures of group " .. only .. " are in the selection.")
        return
    end
    local gNo, gName = storeFrom(r)
    local undo = CreateUndo("GridForge Matrix")
    local lines = math.ceil(n / p.cols)
    local note = (p.snake and (lines < 2 or p.cols < 2)) and "   NOTE: snake has no effect (only one line)" or ""
    finish("Matrix", list, string.format("%s %d  space %d/%d  gap every %d size %d  snake %s  byCols %s  start0 %s%s%s",
        p.byColumns and "rows" or "cols", p.cols, p.sx, p.sy, p.gapEvery, p.gapSize, tostring(p.snake),
        tostring(p.byColumns), tostring(p.start0),
        only and string.format("   only group %d (%d fixtures, place %s)", only, n, place) or "", note), undo, gNo, gName)
    CloseUndo(undo)
end

local DIRS = { "DR", "UR", "DL", "UL" }
local function runDiagonal()
    local list = needSelection("Diagonal")
    if not list then return end
    local inputs = {
        { name = "1 Step X", value = "1", whitefilter = "0123456789", vkPlugin = "NumericInput" },
        { name = "2 Step Y", value = "1", whitefilter = "0123456789", vkPlugin = "NumericInput" },
        { name = "3 Zigzag height", value = "3", whitefilter = "0123456789", vkPlugin = "NumericInput" },
        { name = "4 Block size", value = "3", whitefilter = "0123456789", vkPlugin = "NumericInput" },
        { name = "5 Block overlap", value = "0", whitefilter = "0123456789", vkPlugin = "NumericInput" },
    }
    local selectors = {
        { name = "Shape", selectedValue = 1, type = 1,
          values = { ["Line"] = 1, ["Zigzag"] = 2, ["Blocks flat"] = 3, ["Blocks tall"] = 4 } },
        { name = "Direction", selectedValue = 1, type = 1,
          values = { ["Down/Right"] = 1, ["Up/Right"] = 2, ["Down/Left"] = 3, ["Up/Left"] = 4 } },
        { name = "Start at", selectedValue = 1, type = 1, values = { ["First"] = 1, ["Last"] = 2 } },
    }
    groupInputs(inputs, selectors)
    storeInputs(inputs)
    local r = MessageBox({
        title = "GridForge - Diagonal",
        message = string.format("%d fixtures selected (selection order)\n"
            .. "Line: one diagonal.  Zigzag: goes 'height' rows, then turns back\n"
            .. "Blocks: 'block size' fixtures side by side (flat) or on top (tall),\n"
            .. "   every block one step further\n"
            .. "Block overlap: next block starts N cells under the end of the previous one\n"
            .. "Step: cells per step in X and Y\n"
            .. "Start at 0: top-left of the result at 0/0 (all fixtures only)" .. GROUP_HELP, #list),
        commands = { { value = 1, name = "Apply" }, { value = 0, name = "Cancel" } },
        inputs = inputs,
        selectors = selectors,
        states = { { name = "Start at 0", state = false } },
    })
    if not r or r.result ~= 1 then logLine("%s: cancelled (%d selected)", "Diagonal", #list) return end
    local p = {
        dir = DIRS[r.selectors["Direction"] or 1] or "DR",
        fromLast = (r.selectors["Start at"] == 2),
        sx = num(r.inputs["1 Step X"], 1), sy = num(r.inputs["2 Step Y"], 1),
        shape = ({ "Line", "Zigzag", "Blocks", "Blocks" })[r.selectors["Shape"] or 1] or "Line",
        tall = (r.selectors["Shape"] == 4),
        height = math.max(2, num(r.inputs["3 Zigzag height"], 3)),
        block = math.max(1, num(r.inputs["4 Block size"], 3)),
        overlap = math.max(0, num(r.inputs["5 Block overlap"], 0)),
        start0 = r.states["Start at 0"] and true or false,
    }
    local order, only, place = groupFrom(r, list, "Diagonal")
    if order == false then return end
    local n = arrange(list, order, layoutDiagonal, p, place)
    if n == 0 then
        logLine("Diagonal: none of group %d is in the selection", only)
        msg("GridForge - Diagonal", "None of the fixtures of group " .. only .. " are in the selection.")
        return
    end
    local gNo, gName = storeFrom(r)
    local undo = CreateUndo("GridForge Diagonal")
    local shapeTxt = p.shape
    if p.shape == "Zigzag" then shapeTxt = "Zigzag h" .. p.height
    elseif p.shape == "Blocks" then
        shapeTxt = "Blocks " .. p.block .. (p.tall and " tall" or " flat") .. " overlap " .. p.overlap
    end
    finish("Diagonal", list, string.format("%s  dir %s  fromLast %s  step %d/%d  start0 %s%s",
        shapeTxt, p.dir, tostring(p.fromLast), p.sx, p.sy, tostring(p.start0),
        only and string.format("   only group %d (%d fixtures, place %s)", only, n, place) or ""), undo, gNo, gName)
    CloseUndo(undo)
end

local RSTART = { "Top", "Right", "Bottom", "Left" }
local function runRing()
    local list = needSelection("Ring")
    if not list then return end
    local inputs = {
        { name = "1 Radius (0 = auto)", value = "0", whitefilter = "0123456789", vkPlugin = "NumericInput" },
        { name = "2 Ring sizes (e.g. 1,6,12)", value = "" },
        { name = "3 Ring gap", value = "2", whitefilter = "0123456789", vkPlugin = "NumericInput" },
    }
    local selectors = {
        { name = "Fill rings from", selectedValue = 1, type = 1, values = { ["Centre"] = 1, ["Outside"] = 2 } },
        { name = "First fixture at", selectedValue = 1, type = 1,
          values = { ["Top"] = 1, ["Right"] = 2, ["Bottom"] = 3, ["Left"] = 4 } },
        { name = "Direction", selectedValue = 1, type = 1, values = { ["Clockwise"] = 1, ["Counter-clockwise"] = 2 } },
    }
    groupInputs(inputs, selectors)
    storeInputs(inputs)
    local r = MessageBox({
        title = "GridForge - Ring",
        message = string.format("%d fixtures selected (selection order)\n"
            .. "Radius 0 = smallest circle without two fixtures on one cell\n"
            .. "Ring sizes: several rings, centre out, e.g. 1,6,12 (empty = one ring)\n"
            .. "   1 as the first size = one fixture in the middle\n"
            .. "Ring gap: at least this many cells between rings (bigger = rounder)\n"
            .. "Fill rings from: which ring gets the first selected fixtures\n"
            .. "Start at 0: top-left of the result at 0/0 (all fixtures only)" .. GROUP_HELP, #list),
        commands = { { value = 1, name = "Apply" }, { value = 0, name = "Cancel" } },
        inputs = inputs,
        selectors = selectors,
        states = { { name = "Start at 0", state = false } },
    })
    if not r or r.result ~= 1 then logLine("Ring: cancelled (%d selected)", #list) return end
    local p = {
        radius = num(r.inputs["1 Radius (0 = auto)"], 0),
        gap = math.max(1, num(r.inputs["3 Ring gap"], 1)),
        fromOutside = (r.selectors["Fill rings from"] == 2),
        start = RSTART[r.selectors["First fixture at"] or 1] or "Top",
        ccw = (r.selectors["Direction"] == 2),
        start0 = r.states["Start at 0"] and true or false,
    }
    p.sizes = {}
    for v in tostring(r.inputs["2 Ring sizes (e.g. 1,6,12)"] or ""):gmatch("%d+") do p.sizes[#p.sizes + 1] = tonumber(v) end
    local order, only, place = groupFrom(r, list, "Ring")
    if order == false then return end
    local n = arrange(list, order, layoutRing, p, place)
    if n == 0 then
        logLine("Ring: none of group %d is in the selection", only)
        msg("GridForge - Ring", "None of the fixtures of group " .. only .. " are in the selection.")
        return
    end
    local gNo, gName = storeFrom(r)
    local undo = CreateUndo("GridForge Ring")
    local want = table.concat(p.sizes, ",")
    local got = table.concat(p.fitted or {}, ",")
    local sizeNote = (want ~= "" and want ~= got) and ("   NOTE: sizes " .. want .. " did not fit " .. n .. " fixtures, used " .. got) or ""
    finish("Ring", list, string.format("rings %s  radii %s  gap %d  from %s  first at %s  %s  start0 %s%s%s",
        got, table.concat(p.radii or {}, ","), p.gap, p.fromOutside and "outside" or "centre",
        p.start, p.ccw and "CCW" or "CW",
        tostring(p.start0),
        only and string.format("   only group %d (%d fixtures, place %s)", only, n, place) or "", sizeNote),
        undo, gNo, gName)
    if sizeNote ~= "" then msg("GridForge - Ring", "Ring sizes " .. want .. " = not " .. n .. " fixtures.\nUsed: " .. got) end
    CloseUndo(undo)
end

local function sameSet(a, b)
    if #a ~= #b then return false end
    local s = {}
    for _, e in ipairs(a) do s[e.addr] = true end
    for _, e in ipairs(b) do if not s[e.addr] then return false end end
    return true
end

local function runMirror()
    local cur = readSelection()
    local src = loadMirror()
    if #src == 0 or (sameSet(src, cur) and #cur > 0) then
        if #cur == 0 then
            logLine("Mirror: nothing selected, nothing recorded")
            msg("GridForge - Mirror", "Step 1: select the half you placed, then run Mirror.")
            return
        end
        saveMirror(cur)
        logLine("Mirror step 1: recorded %d  (%s ... %s)", #cur, cur[1].addr, cur[#cur].addr)
        msg("GridForge - Mirror", string.format("Step 1 done: %d fixtures recorded.\n\n"
            .. "Step 2: select the fixtures you have NOT placed\n(same count, in order: row by row)\nand run Mirror again.", #cur))
        return
    end
    -- recorded fixtures that are selected again are not targets
    local inSrc, tgt = {}, {}
    for _, e in ipairs(src) do inSrc[e.addr] = true end
    for _, e in ipairs(cur) do if not inSrc[e.addr] then tgt[#tgt + 1] = e end end
    local ignored = #cur - #tgt
    if ignored > 0 then logLine("Mirror step 2: %d recorded fixtures in the selection ignored", ignored) end
    cur = tgt
    local inputs = { { name = "1 Gap at mirror line", value = "2", whitefilter = "0123456789", vkPlugin = "NumericInput" } }
    storeInputs(inputs)
    local r = MessageBox({
        title = "GridForge - Mirror",
        message = string.format("Recorded half: %d fixtures\nOther half:    %d fixtures%s%s\n\n"
            .. "Gap = distance between the two inner fixtures\n(2 = one empty column in the middle)\n"
            .. "Inner first = the first fixture you selected goes next to the middle\n"
            .. "Outer first = the first fixture you selected goes to the outside",
            #src, #cur, (ignored > 0) and ("  (" .. ignored .. " recorded ones ignored)") or "",
            (#cur ~= #src) and "\n\nCOUNTS DIFFER" or ""),
        commands = { { value = 1, name = "Mirror" }, { value = 2, name = "Record again" },
                     { value = 3, name = "Forget" }, { value = 0, name = "Cancel" } },
        inputs = inputs,
        selectors = {
            { name = "Axis", selectedValue = 1, type = 1, values = { ["Left|Right (X)"] = 1, ["Top|Bottom (Y)"] = 2 } },
            { name = "Pairing", selectedValue = 1, type = 1, values = { ["Inner first"] = 1, ["Outer first"] = 2 } },
        },
        states = { { name = "Start at 0", state = false } },
    })
    if not r or r.result == 0 then logLine("Mirror: cancelled (recorded %d, selected %d)", #src, #cur) return end
    if r.result == 3 then clearMirror(); logLine("Mirror: recorded half forgotten"); msg("GridForge - Mirror", "Recorded half cleared.") return end
    if r.result == 2 then
        if #cur == 0 then return end
        saveMirror(cur)
        logLine("Mirror: recorded again %d  (%s ... %s)", #cur, cur[1].addr, cur[#cur].addr)
        msg("GridForge - Mirror", string.format("%d fixtures recorded.\nSelect the other half and run Mirror again.", #cur))
        return
    end
    if #cur == 0 then logLine("Mirror step 2: nothing selected") msg("GridForge - Mirror", "Select the other half first.") return end
    if #cur ~= #src then
        logLine("Mirror step 2: counts differ, recorded %d, selected %d", #src, #cur)
        msg("GridForge - Mirror", string.format("Recorded %d, selected %d.\nThe counts must be the same.", #src, #cur))
        return
    end
    local p = {
        axis = (r.selectors["Axis"] == 2) and "Y" or "X",
        gap = math.max(1, num(r.inputs["1 Gap at mirror line"], 2)),
        innerFirst = (r.selectors["Pairing"] ~= 2),
        start0 = r.states["Start at 0"] and true or false,
    }
    local all = layoutMirror(src, cur, p)
    local gNo, gName = storeFrom(r)
    local undo = CreateUndo("GridForge Mirror")
    local bad = finish("Mirror", all, string.format("axis %s  gap %d  innerFirst %s  start0 %s",
        p.axis, p.gap, tostring(p.innerFirst), tostring(p.start0)), undo, gNo, gName)
    CloseUndo(undo)
    if bad == 0 then clearMirror() end
end

local COPY_PLACES = { "Keep", "Row", "Column", "Grid", "Stack" }
local function runCopy()
    local cur = readSelection()
    local src = loadRec(COPY_VAR)
    local function record(list, again)
        saveRec(COPY_VAR, list)
        logLine("Copy: %s shape of %d  (%s ... %s)", again and "recorded again" or "step 1: recorded",
            #list, list[1].addr, list[#list].addr)
        msg("GridForge - Copy", string.format("Shape recorded: %d fixtures.\n\n"
            .. "Step 2: select one or more groups of %d fixtures\n(one after the other) and run Copy again.", #list, #list))
    end
    if #src == 0 or (#cur > 0 and sameSet(src, cur)) then
        if #cur == 0 then
            logLine("Copy: nothing selected, nothing recorded")
            msg("GridForge - Copy", "Step 1: select the shape to copy, then run Copy.")
            return
        end
        return record(cur)
    end
    -- recorded fixtures in the selection get the recorded shape back
    local inSrc, tgt, keep = {}, {}, {}
    for _, e in ipairs(src) do inSrc[e.addr] = e end
    for _, e in ipairs(cur) do
        local s0 = inSrc[e.addr]
        if s0 then e.nx, e.ny, e.z = s0.x, s0.y, s0.z; keep[#keep + 1] = e else tgt[#tgt + 1] = e end
    end
    local fits = (#tgt > 0 and #tgt % #src == 0)
    local inputs = {
        { name = "1 Copies per row (Grid)", value = "5", whitefilter = "0123456789", vkPlugin = "NumericInput" },
        { name = "2 Gap between copies", value = "1", whitefilter = "0123456789", vkPlugin = "NumericInput" },
    }
    storeInputs(inputs)
    local r = MessageBox({
        title = "GridForge - Copy",
        message = string.format("Recorded shape: %d fixtures\nSelected:       %d fixtures%s\n%s\n\n"
            .. "Keep = each copy starts where its fixtures are now\n"
            .. "In a row / column = copies next to the recorded shape\n"
            .. "Grid = recorded shape first, then 'copies per row' in each row\n"
            .. "Stack on shape (tick box below) = all copies on the same cells as the shape (same 0), Place is ignored\n"
            .. "The recorded fixtures (if selected) get their recorded shape back",
            #src, #tgt, (#keep > 0) and ("  (" .. #keep .. " recorded ones included)") or "",
            fits and string.format("= %d copies", #tgt / #src)
                 or string.format("NOT a multiple of %d", #src)),
        commands = { { value = 1, name = "Copy" }, { value = 2, name = "Record again" },
                     { value = 3, name = "Forget" }, { value = 0, name = "Cancel" } },
        inputs = inputs,
        selectors = { { name = "Place", selectedValue = 4, type = 1,          -- 4 buttons fit the window ; the 5th one (Stack) is a tick box
                        values = { ["Keep"] = 1, ["In a row"] = 2, ["In a column"] = 3, ["Grid"] = 4 } } },
        states = { { name = "Stack on shape", state = false } },
    })
    if not r or r.result == 0 then logLine("Copy: cancelled (shape %d, selected %d)", #src, #tgt) return end
    if r.result == 3 then
        clearRec(COPY_VAR); logLine("Copy: recorded shape forgotten")
        msg("GridForge - Copy", "Recorded shape cleared.")
        return
    end
    if r.result == 2 then
        if #cur == 0 then return end
        return record(cur, true)
    end
    if not fits then
        logLine("Copy: %d selected is not a multiple of %d", #tgt, #src)
        msg("GridForge - Copy", string.format("Selected %d, the shape has %d.\nSelect whole groups of %d.",
            #tgt, #src, #src))
        return
    end
    local chunks = {}
    for i, e in ipairs(tgt) do
        local c = math.floor((i - 1) / #src) + 1
        chunks[c] = chunks[c] or {}
        table.insert(chunks[c], e)
    end
    local p = {
        place = (r.states and r.states["Stack on shape"]) and "Stack" or (COPY_PLACES[r.selectors["Place"] or 4] or "Grid"),
        perRow = math.max(1, num(r.inputs["1 Copies per row (Grid)"], 5)),
        gap = math.max(0, num(r.inputs["2 Gap between copies"], 1)),
    }
    layoutCopy(src, chunks, p)
    local all = {}
    for _, e in ipairs(cur) do all[#all + 1] = e end
    local gNo, gName = storeFrom(r)
    local undo = CreateUndo("GridForge Copy")
    finish("Copy", all, string.format("shape %d  copies %d  place %s%s  gap %d  recorded ones included %d",
        #src, #chunks, p.place, (p.place == "Grid") and (" " .. p.perRow .. " per row") or "", p.gap, #keep),
        undo, gNo, gName, p.place == "Stack")
    CloseUndo(undo)
    if p.place == "Stack" then doGridStore(true) end
end

-- ---------------------------------------------------------------
-- GridStore / Reset (fixture type grid)
-- ---------------------------------------------------------------
local function doGridStore(ask)
    local n = #readSelection()
    if n == 0 then msg("GridForge - GridStore", "Nothing selected.") return end
    if ask then
        local r = MessageBox({
            title = "GridForge - GridStore",
            message = string.format("Store the grid of the %d selected fixtures\n"
                .. "to their FIXTURE TYPE (every fixture of that type).\n\n"
                .. "Oops can NOT undo this.\nUse GridForge Reset to go back to Auto.", n),
            commands = { { value = 1, name = "GridStore" }, { value = 0, name = "Not now" } },
        })
        if not r or r.result ~= 1 then logLine("GridStore: not done (%d selected)", n) return end
    end
    local res = safe(function() return Cmd("GridStore /NoConfirm") end)
    logLine("GridStore: %d fixtures -> %s", n, tostring(res))
    Printf("GridForge GridStore: %d fixtures -> %s", n, tostring(res))
end

local FT_DIAG = {}
local function fixtureTypesOfSelection()
    local fts, order = {}, {}
    local all = safe(function() return Patch().FixtureTypes:Children() end) or {}
    local seenFid = {}
    FT_DIAG = {}
    for _, e in ipairs(readSelection()) do
        local fid = tonumber(e.addr:match("Fixture%s+(%d+)"))
        if fid and not seenFid[fid] then
            seenFid[fid] = true
            local h = safe(function() return ObjectList("Fixture " .. fid)[1] end)
            local ftName = h and tostring(safe(function() return h:Get("FixtureType", Enums.Roles.Display) end) or "") or ""
            local bare = ftName:gsub("^%s*%d+%s+", "")
            -- 1) the handle itself, 2) exact name, 3) name contained
            local found = h and safe(function() return h:Get("FixtureType") end)
            if type(found) ~= "userdata" or not safe(function() return found:Children() end) then found = nil end
            local how = found and "handle" or nil
            if not found then
                for _, ft in ipairs(all) do
                    if tostring(safe(function() return ft.name end) or "") == bare then found = ft; how = "exact" break end
                end
            end
            if not found then
                for _, ft in ipairs(all) do
                    local nm = tostring(safe(function() return ft.name end) or "")
                    if nm ~= "" and ftName:find(nm, 1, true) then found = ft; how = "contains" break end
                end
            end
            FT_DIAG[#FT_DIAG + 1] = string.format("fixture %d: type '%s' -> %s (%s)", fid, ftName,
                found and tostring(safe(function() return found.name end)) or "NOT FOUND", tostring(how))
            if found then
                local key = tostring(safe(function() return found.no end) or "") .. " " .. tostring(safe(function() return found.name end) or "?")
                if not fts[key] then fts[key] = found; order[#order + 1] = key end
            end
        end
    end
    for _, ft in ipairs(all) do
        FT_DIAG[#FT_DIAG + 1] = string.format("  in patch: %s %s", tostring(safe(function() return ft.no end)),
            tostring(safe(function() return ft.name end)))
    end
    return fts, order
end

-- property access by the REAL property name (found by scanning, any case)
local function propName(h, want)
    local n = safe(function() return h:PropertyCount() end) or 0
    for i = 0, n - 1 do
        local nm = safe(function() return h:PropertyName(i) end)
        if nm and tostring(nm):upper() == want then return tostring(nm) end
    end
    return nil
end
local function getP(h, want)
    local nm = propName(h, want)
    if not nm then return nil, nil end
    return tostring(safe(function() return h:Get(nm, Enums.Roles.Display) end)), nm
end

-- every geometry below the fixture type that has a Grid Auto property
local function gridGeometries(ft)
    local list = {}
    local function walk(h, depth)
        for _, c in ipairs(safe(function() return h:Children() end) or {}) do
            local v, nm = getP(c, "GRIDAUTO")
            if nm then
                list[#list + 1] = { h = c, auto = v, prop = nm,
                    name = tostring(safe(function() return c.name end) or "?"),
                    cls = tostring(safe(function() return c:GetClass() end) or "?"),
                    gx = getP(c, "GRIDX"), gy = getP(c, "GRIDY") }
            end
            if depth < 8 then walk(c, depth + 1) end
        end
    end
    walk(ft, 0)
    if #list == 0 then
        local geos = safe(function() return ft.Geometries end)
        if geos then walk(geos, 0) end
    end
    return list
end
local function manualGeometries(ft)
    local out = {}
    for _, g in ipairs(gridGeometries(ft)) do
        if g.auto ~= "Auto" then out[#out + 1] = g end
    end
    return out
end

-- try the ways Lua may set the property, keep the first that works
local SETTERS = {
    function(g) g.h:Set(g.prop, "Auto") end,
    function(g) g.h[g.prop] = "Auto" end,
    function(g) g.h:Set(g.prop, "0") end,
    function(g) g.h:Set(g.prop, 0) end,
    function(g) g.h:Set(g.prop, "Yes") end,
}
local function runReset()
    local fts, order = fixtureTypesOfSelection()
    if #order == 0 then
        msg("GridForge - Reset", "Select a fixture (or its parts) of the type to reset.")
        return
    end
    local lines, total, geos, diag = {}, 0, {}, { string.format("GridForge %s  Reset - geometry grid table", VERSION) }
    for _, nm in ipairs(order) do
        local all = gridGeometries(fts[nm])
        geos[nm] = manualGeometries(fts[nm])
        total = total + #geos[nm]
        lines[#lines + 1] = string.format("%-28s %d of %d geometries not Auto", nm, #geos[nm], #all)
        diag[#diag + 1] = string.format("%s: %d geometries with a grid, %d not Auto", nm, #all, #geos[nm])
        for i, g in ipairs(all) do
            if i <= 80 or g.auto ~= "Auto" then
                diag[#diag + 1] = string.format("  %-9s %-22s %-8s x %-4s y %-4s  (%s)", g.cls:sub(1, 9), g.name,
                    tostring(g.auto), tostring(g.gx), tostring(g.gy), g.prop)
            end
        end
    end
    for _, l in ipairs(FT_DIAG) do diag[#diag + 1] = l end
    logRun(diag)
    if total == 0 then
        logLine("Reset: nothing manual in %s", table.concat(order, ", "))
        msg("GridForge - Reset", "Nothing to reset - all geometries are already Auto:\n\n" .. table.concat(lines, "\n"))
        return
    end
    local r = MessageBox({
        title = "GridForge - Reset",
        message = "Set Grid Auto back to Auto (fixture type default):\n\n" .. table.concat(lines, "\n")
            .. "\n\nThis changes the fixture types (every fixture of that type).",
        commands = { { value = 1, name = "Reset" }, { value = 0, name = "Cancel" } },
    })
    if not r or r.result ~= 1 then logLine("Reset: cancelled") return end
    local rep = { string.format("GridForge %s  Reset", VERSION) }
    local done, failed, used = 0, 0, nil
    for _, nm in ipairs(order) do
        for _, g in ipairs(geos[nm]) do
            local ok = false
            local tries = used and { SETTERS[used] } or SETTERS
            for i, f in ipairs(tries) do
                safe(f, g)
                if getP(g.h, "GRIDAUTO") == "Auto" then
                    ok = true
                    used = used or i
                    break
                end
            end
            if ok then done = done + 1 else failed = failed + 1 end
        end
        rep[#rep + 1] = string.format("%-28s %d geometries", nm, #geos[nm])
    end
    rep[#rep + 1] = string.format("reset %d, failed %d, method %s", done, failed, tostring(used))
    logRun(rep)
    msg("GridForge - Reset", string.format("Reset to Auto: %d\nFailed: %d%s", done, failed,
        (failed > 0) and "\n\nThe rest can be set in the fixture type editor:\nGeometries -> Grid Auto -> Auto" or ""))
end

-- sync (pure): comb = current combined group {addr,x,y,z},
-- parts = list of part groups (lists of {addr,x,y,z}).
-- Every part keeps its offset in the combined group (found from the
-- first of its fixtures that is already there); a new part goes
-- below everything. Returns the new list (nx, ny set) and a note.
local function layoutSync(comb, parts)
    local inComb = {}
    for _, e in ipairs(comb) do inComb[e.addr] = e end
    local out, used, newParts, placedBottom = {}, {}, 0, nil
    local cb = (#comb > 0) and bounds(comb) or nil
    local bottom = cb and cb.maxY or -2
    for _, part in ipairs(parts) do
        local dx, dy
        for _, e in ipairs(part) do
            local c = inComb[e.addr]
            if c then dx, dy = c.x - e.x, c.y - e.y break end
        end
        if not dx then
            local pb = bounds(part)
            dx, dy = ((cb and cb.minX) or 0) - pb.minX, bottom + 2 - pb.minY
            newParts = newParts + 1
        end
        for _, e in ipairs(part) do
            if not used[e.addr] then
                used[e.addr] = true
                e.nx, e.ny = e.x + dx, e.y + dy
                out[#out + 1] = e
            end
        end
        local ob = bounds(part)
        if ob.maxY + dy > bottom then bottom = ob.maxY + dy end
    end
    local dropped = 0
    for _, e in ipairs(comb) do if not used[e.addr] then dropped = dropped + 1 end end
    return out, newParts, dropped
end

local function readGroupFull(no)
    Cmd("Selection 2"); Cmd("ClearSelection"); Cmd("Group " .. no)
    local g = readSelection()
    Cmd("ClearSelection"); Cmd("Selection 1")
    return g
end

local function runSync()
    local lastC = safe(function() return GetVar(GlobalVars(), SYNC_VAR .. "LAST") end) or ""
    local r = MessageBox({
        title = "GridForge - Sync",
        message = "Rebuild a combined group from its parts.\n"
            .. "Each part keeps its place in the combined group,\n"
            .. "but gets the layout it has now in its own group.\n"
            .. "A part that is not in the combined group yet goes below.\n"
            .. "Parts empty = the parts remembered for this group.",
        commands = { { value = 1, name = "Sync" }, { value = 0, name = "Cancel" } },
        inputs = {
            { name = "1 Combined group", value = tostring(lastC), whitefilter = "0123456789", vkPlugin = "NumericInput" },
            { name = "2 Part groups (e.g. 1,2)", value = "" },
        },
    })
    if not r or r.result ~= 1 then logLine("Sync: cancelled") return end
    local C = num(r.inputs["1 Combined group"], nil)
    if not C then msg("GridForge - Sync", "Type the number of the combined group.") return end
    local txt = trim(r.inputs["2 Part groups (e.g. 1,2)"])
    if txt == "" then txt = tostring(safe(function() return GetVar(GlobalVars(), SYNC_VAR .. C) end) or "") end
    local nums = {}
    for v in txt:gmatch("%d+") do if tonumber(v) ~= C then nums[#nums + 1] = tonumber(v) end end
    if #nums == 0 then
        logLine("Sync: no part groups for group %d", C)
        msg("GridForge - Sync", "No part groups known for group " .. C .. ".\nType them, e.g. 1,2")
        return
    end
    local comb = readGroupFull(C)
    local parts, missing = {}, {}
    for _, n in ipairs(nums) do
        local g = readGroupFull(n)
        if #g > 0 then parts[#parts + 1] = g else missing[#missing + 1] = n end
    end
    if #parts == 0 then msg("GridForge - Sync", "The part groups are empty.") return end
    local list, newParts, dropped = layoutSync(comb, parts)
    safe(function() SetVar(GlobalVars(), SYNC_VAR .. C, table.concat(nums, ",")) end)
    safe(function() SetVar(GlobalVars(), SYNC_VAR .. "LAST", tostring(C)) end)
    local undo = CreateUndo("GridForge Sync")
    local rep = {}
    rep[#rep + 1] = string.format("GridForge %s  Sync", VERSION)
    rep[#rep + 1] = string.format("combined %d  parts %s  new parts %d  dropped %d%s", C, table.concat(nums, ","),
        newParts, dropped, (#missing > 0) and ("  empty parts: " .. table.concat(missing, ",")) or "")
    -- build in buffer 2, store, back to your selection
    Cmd("Selection 2")
    local bad, n = place(list, undo, rep)
    Cmd("Store Group " .. C .. " /Overwrite", undo)
    Cmd("ClearSelection"); Cmd("Selection 1")
    rep[#rep + 1] = string.format("%d fixtures, placed %d, problems %d   stored to group %d", #list, n, bad, C)
    dumpList(rep, list)
    logRun(rep)
    CloseUndo(undo)
    Printf("GridForge Sync: group %d from %s, %d fixtures, %d problems", C, table.concat(nums, ","), #list, bad)
end

-- ---------------------------------------------------------------
-- test mode: fixtures TEST_FIRST..TEST_LAST, selection buffer 2
-- ---------------------------------------------------------------
local function runTest()
    local rep = {}
    local function r(fmt, ...) rep[#rep + 1] = string.format(fmt, ...) end
    local bd = safe(BuildDetails) or {}
    r("===== GridForge %s test  (%s %s) =====", VERSION, tostring(bd.BigVersion), tostring(bd.HostType))
    local undo = CreateUndo("GridForge test")
    local function selectRange(a, b)
        Cmd("ClearSelection")
        for f = a, b do Cmd("Fixture " .. f) end
        return readSelection()
    end
    local function case(name, build)
        r("")
        r("--- %s ---", name)
        Cmd("Selection 2")
        local ok, err = pcall(function()
            local list, params = build()
            if not list or #list == 0 then r("no fixtures") return end
            r("%s", params)
            local bad, n = place(list, undo, rep)
            r("%-8s fixtures %d  placed %d  problems %d  %s", name, #list, n, bad, bad == 0 and "OK" or "CHECK")
            dumpList(rep, list, 12)
        end)
        if not ok then r("ERROR %s", tostring(err)) end
        Cmd("ClearSelection"); Cmd("Selection 1")
    end
    local half = TEST_FIRST + math.floor((TEST_LAST - TEST_FIRST + 1) / 2) - 1
    case("Matrix", function()
        local l = selectRange(TEST_FIRST, TEST_LAST)
        local p = { cols = 4, sx = 2, sy = 3, gapEvery = 2, gapSize = 1, snake = true, byColumns = false }
        arrange(l, nil, layoutMatrix, p)
        return l, "cols 4  space 2/3  gap every 2 size 1  snake"
    end)
    case("Diagonal", function()
        local l = selectRange(TEST_FIRST, TEST_LAST)
        arrange(l, nil, layoutDiagonal, { dir = "UR", fromLast = false, sx = 2, sy = 1 })
        return l, "Up/Right  step 2/1"
    end)
    case("Zigzag", function()
        local l = selectRange(TEST_FIRST, TEST_LAST)
        arrange(l, nil, layoutDiagonal, { dir = "DR", sx = 1, sy = 1, shape = "Zigzag", height = 3 })
        return l, "Zigzag height 3, Down/Right"
    end)
    case("Blocks", function()
        local l = selectRange(TEST_FIRST, TEST_LAST)
        arrange(l, nil, layoutDiagonal, { dir = "UR", sx = 1, sy = 1, shape = "Blocks", block = 3 })
        return l, "Blocks 3 flat, Up/Right"
    end)
    case("BlkOvl", function()
        local l = selectRange(TEST_FIRST, TEST_LAST)
        arrange(l, nil, layoutDiagonal, { dir = "DR", sx = 1, sy = 1, shape = "Blocks", block = 3, overlap = 1 })
        return l, "Blocks 3 flat, overlap 1, Down/Right"
    end)
    case("Ring", function()
        local l = selectRange(TEST_FIRST, TEST_LAST)
        local p = { radius = 0, start = "Top", ccw = false }
        arrange(l, nil, layoutRing, p)
        return l, "Ring auto radius -> " .. tostring(p.usedRadius)
    end)
    case("Rings", function()
        local l = selectRange(TEST_FIRST, TEST_LAST)
        local p = { sizes = { 1, 3, 6 }, gap = 1, start = "Top" }
        arrange(l, nil, layoutRing, p)
        return l, "Rings 1,3,6 -> radii " .. table.concat(p.radii, ",")
    end)
    case("Copy", function()
        -- shape: first 2 fixtures as a small diagonal, copied 4x in a row
        local src = selectRange(TEST_FIRST, TEST_FIRST + 1)
        src[1].x, src[1].y, src[2].x, src[2].y = 0, 0, 1, 1
        local l = selectRange(TEST_FIRST, TEST_LAST)
        for i = 1, 2 do l[i].nx, l[i].ny = l[i].x, l[i].y end
        l[1].nx, l[1].ny, l[2].nx, l[2].ny = 0, 0, 1, 1
        local chunks = {}
        for i = 3, #l do
            local c = math.floor((i - 3) / 2) + 1
            chunks[c] = chunks[c] or {}
            table.insert(chunks[c], l[i])
        end
        layoutCopy(src, chunks, { place = "Grid", perRow = 3, gap = 1 })
        return l, "shape of 2 copied " .. #chunks .. "x, grid 3 per row"
    end)
    case("Free", function()
        -- first half stays at 0..4 / 0, second half keeps its place on top of it -> moved right
        local l = selectRange(TEST_FIRST, TEST_LAST)
        local o1, o2 = {}, {}
        for i, e in ipairs(l) do
            e.x, e.y = (i <= #l // 2) and (i - 1) or (i - 1 - #l // 2), 0
            if i <= #l // 2 then o1[#o1 + 1] = e.addr else o2[#o2 + 1] = e.addr end
        end
        local p = { sx = 1, sy = 1, dir = "DR" }
        arrange(l, o2, layoutDiagonal, p, "Free")
        return l, "second half diagonal on top of the first -> Free moved it " .. tostring(p.freeShift)
    end)
    case("Sync", function()
        -- combined: part A (1-5) at 0/0.., part B (6-10) at 0/3..; B gets a new inner layout
        local l = selectRange(TEST_FIRST, TEST_LAST)
        local comb, A, B = {}, {}, {}
        for i, e in ipairs(l) do
            if i <= #l // 2 then
                comb[#comb + 1] = { addr = e.addr, x = i - 1, y = 0, z = 0 }
                A[#A + 1] = { addr = e.addr, x = i - 1, y = 0, z = 0 }
            else
                local k = i - 1 - #l // 2
                comb[#comb + 1] = { addr = e.addr, x = k, y = 3, z = 0 }
                B[#B + 1] = { addr = e.addr, x = k, y = k, z = 0 }   -- new layout: diagonal
            end
        end
        local out, newParts, dropped = layoutSync(comb, { A, B })
        return out, "part B keeps its place (y 3) with its new diagonal, new " .. newParts .. " dropped " .. dropped
    end)
    case("Start0", function()
        local l = selectRange(TEST_FIRST, TEST_LAST)
        for _, e in ipairs(l) do e.nx, e.ny = e.x + 5, e.y + 4 end
        place(l, undo, rep)                      -- move away from 0/0 first
        l = readSelection()
        arrange(l, nil, layoutDiagonal, { dir = "DR", fromLast = true, sx = 1, sy = 1, start0 = true })
        return l, "Down/Right from last, start at 0 (was at 5/4)"
    end)
    case("OnlyGrp", function()
        -- first half as a 3-column matrix, then only the second half -> right of rest
        local l = selectRange(TEST_FIRST, TEST_LAST)
        local order1, order2 = {}, {}
        for i, e in ipairs(l) do
            if i <= #l // 2 then order1[#order1 + 1] = e.addr else order2[#order2 + 1] = e.addr end
        end
        arrange(l, order1, layoutMatrix, { cols = 3, sx = 1, sy = 1, gapEvery = 0, gapSize = 0 }, "Keep")
        place(l, undo, rep)
        l = readSelection()
        local n = arrange(l, order2, layoutDiagonal, { dir = "DR", sx = 1, sy = 1 }, "Right")
        return l, "first half 3-col matrix, then only " .. n .. " fixtures diagonal, right of rest"
    end)
    case("Mirror", function()
        local src = selectRange(TEST_FIRST, half)
        -- place the source as a small shape first: two rows
        for i, e in ipairs(src) do e.nx = (i - 1) % 3; e.ny = math.floor((i - 1) / 3) * 2 end
        place(src, undo, rep)
        src = readSelection()
        local tgt = selectRange(half + 1, TEST_LAST)
        local all = layoutMirror(src, tgt, { axis = "X", gap = 2, innerFirst = true, start0 = false })
        return all, "source " .. #src .. "  target " .. #tgt .. "  axis X gap 2 inner first"
    end)
    CloseUndo(undo)
    local path = writeFile("GF_test.txt", rep)
    Printf("GridForge test: report " .. tostring(path))
end

-- ---------------------------------------------------------------
local function main(displayHandle, argument)
    local arg = tostring(argument or ""):lower()
    if FORCE_TEST or arg == "test" then return runTest() end
    if arg == "matrix" then return runMatrix() end
    if arg == "diagonal" then return runDiagonal() end
    if arg == "mirror" then return runMirror() end
    if arg == "ring" then return runRing() end
    if arg == "copy" then return runCopy() end
    if arg == "sync" then return runSync() end
    if arg == "gridstore" then return doGridStore(true) end
    if arg == "reset" then return runReset() end
    local r = MessageBox({
        title = "GridForge " .. VERSION,
        message = "Selection Grid tools for the current selection.\nPick a tool:",
        commands = { { value = 1, name = "Matrix" }, { value = 2, name = "Diagonal" },
                     { value = 4, name = "Ring" }, { value = 3, name = "Mirror" },
                     { value = 5, name = "Copy" }, { value = 6, name = "Sync" },
                     { value = 7, name = "GridStore" }, { value = 8, name = "Reset" },
                     { value = 0, name = "Cancel" } },
    })
    if not r then return end
    if r.result == 1 then runMatrix()
    elseif r.result == 2 then runDiagonal()
    elseif r.result == 3 then runMirror()
    elseif r.result == 4 then runRing()
    elseif r.result == 5 then runCopy()
    elseif r.result == 6 then runSync()
    elseif r.result == 7 then doGridStore(true)
    elseif r.result == 8 then runReset() end
end

return main
