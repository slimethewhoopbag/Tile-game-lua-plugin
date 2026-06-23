--!nonstrict
--[[ PathGenerator — ServerScriptService > Modules > PathGenerator (ModuleScript). REPLACES old one.

	WHAT CHANGED AND WHY
	  (4) Neutralised-hazard clusters on the path. Shock may appear on the safe route
	      when immediately flanked by an Inverter (grounding via Neutralizable), or when
	      a Beacon on the route points straight at it. Lava may appear only when a
	      Beacon points straight at it — Lava is NOT Neutralizable by Inverter, so only
	      a Beacon can switch it off. Both cluster types go through TileRules so
	      generation, gameplay, and visuals always agree on which tiles are safe.
	      The safety backstop at the end of build() still applies as a last resort.
	  (3) The route is strictly ONE tile wide: long horizontal sweeps joined by
	      single-column vertical connectors, ROW_GAP_MIN..ROW_GAP_MAX rows apart.
	  (2) Beacon neutralisation goes through TileRules.beaconTargets, bounded to
	      BeaconRange tiles along PointDir.
	  (1) Hazard safety lives in TileRules. isCellSafe here just forwards.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local TileRules    = require(Shared:WaitForChild("TileRules"))

local PathGenerator = {}

local Directions = TileRules.Directions
local HMOVE = { Left = Directions.Left, Right = Directions.Right }

-- carve tuning -------------------------------------------------------------
local ROW_GAP_MIN = 4
local ROW_GAP_MAX = 5
local SWEEP_MIN   = 3
local FLIP_CHAOS  = 0.20
-- hazard-cluster tuning ----------------------------------------------------
-- HAZARD_CLUSTER_CHANCE: probability of attempting a cluster at any eligible
-- cell. 0.20 → roughly one cluster every 5 cells on average.
local HAZARD_CLUSTER_CHANCE  = 0.20
-- CLUSTER_COOLDOWN_CELLS: minimum ordinary tiles between two clusters so they
-- never directly abut each other.
local CLUSTER_COOLDOWN_CELLS = 3
----------------------------------------------------------------------------

local function key(x, z) return x .. "_" .. z end
local function inBounds(x, z, w, l) return x >= 1 and x <= w and z >= 1 and z <= l end
local function opp(h) return (h == "Left") and "Right" or "Left" end
local function randomH(rng) return (rng:NextInteger(0, 1) == 0) and "Left" or "Right" end
local function randomDir(rng)
	local names = { "Up", "Down", "Left", "Right" }
	return names[rng:NextInteger(1, 4)]
end

-- Returns the cardinal direction name from grid cell a to grid cell b.
-- Every consecutive pair in path[] is exactly 1 grid step apart, so this
-- always returns a valid string for them; nil only for a non-cardinal offset
-- (which never occurs for path[] pairs).
local function dirBetween(a, b)
	local dx, dz = b.x - a.x, b.z - a.z
	if dx ==  1 then return "Right" end
	if dx == -1 then return "Left"  end
	if dz ==  1 then return "Up"    end
	if dz == -1 then return "Down"  end
	return nil
end

local function newGrid(w, l)
	local g = {}
	for x = 1, w do
		g[x] = {}
		for z = 1, l do g[x][z] = { tile = "Stone", onPath = false, attr = {} } end
	end
	return g
end

local function weightedPick(pool, rng)
	local total = 0
	for _, e in ipairs(pool) do total += e.w end
	local r, acc = rng:NextInteger(1, total), 0
	for _, e in ipairs(pool) do
		acc += e.w
		if r <= acc then return e.t end
	end
	return pool[1].t
end

-- World push-direction names keyed by grid direction (matches GameManager/TilePlacer).
local GRID_TO_PUSH   = { Up = "Forward", Down = "Back", Left = "Left", Right = "Right" }
local PUSH_DIR_NAMES = { "Up", "Down", "Left", "Right" }   -- fixed order => deterministic per seed

-- A path Push may only shove the player onto a tile that is ALSO on the path (and so is
-- guaranteed safe once generation finishes). Returns { dirWorld=, power= } for a random
-- legal push from cell c, or nil if no direction/power (1..3) lands on a path tile.
local function pickPushOption(grid, c, rng)
	local opts = {}
	for _, gd in ipairs(PUSH_DIR_NAMES) do
		local d = Directions[gd]
		for p = 1, 3 do
			local nx, nz = c.x + d.dx * p, c.z + d.dz * p
			local col  = grid[nx]
			local dest = col and col[nz]
			if dest and dest.onPath then
				opts[#opts + 1] = { dirWorld = GRID_TO_PUSH[gd], power = p }
			end
		end
	end
	if #opts == 0 then return nil end
	return opts[rng:NextInteger(1, #opts)]
end

function PathGenerator.isCellSafe(grid, x, z)
	return TileRules.isCellSafe(grid, x, z)
end

--========================= carve (1-wide snake, unchanged) =================--
local function carvePath(w, l, rng)
	local visited, path = {}, {}
	local function place(x, z)
		if not visited[key(x, z)] then
			visited[key(x, z)] = true
			table.insert(path, { x = x, z = z })
		end
	end

	local cx = rng:NextInteger(1, w)
	local cz = 1
	place(cx, cz)
	local h = (cx <= w / 2) and "Right" or "Left"

	local function sweep()
		local hm = HMOVE[h]
		local maxRun = (h == "Right") and (w - cx) or (cx - 1)
		if maxRun <= 0 then
			h = opp(h); hm = HMOVE[h]
			maxRun = (h == "Right") and (w - cx) or (cx - 1)
		end
		if maxRun <= 0 then return end
		local run = rng:NextInteger(math.min(SWEEP_MIN, maxRun), maxRun)
		for _ = 1, run do
			local nx = cx + hm.dx
			if not (inBounds(nx, cz, w, l) and not visited[key(nx, cz)]) then break end
			cx = nx
			place(cx, cz)
		end
	end

	local function connectorUp()
		local gap = rng:NextInteger(ROW_GAP_MIN, ROW_GAP_MAX)
		for _ = 1, gap do
			if cz >= l then break end
			cz += 1
			place(cx, cz)
		end
	end

	sweep()
	while cz < l do
		connectorUp()
		if cz >= l then break end
		h = (rng:NextNumber() < FLIP_CHAOS) and randomH(rng) or opp(h)
		sweep()
	end

	while cz < l do cz += 1; place(cx, cz) end
	return path
end

--========================= fill the safe route =============================--
local function fillPath(grid, path, rng)
	local n = #path
	for _, c in ipairs(path) do grid[c.x][c.z].onPath = true end

	local startCell, goalCell = path[1], path[n]
	grid[startCell.x][startCell.z].tile = "Spawn"; grid[startCell.x][startCell.z].attr = {}
	grid[goalCell.x][goalCell.z].tile   = "Goal";  grid[goalCell.x][goalCell.z].attr  = {}

	-- Regular (never-hazard) path tiles. Shock and Lava are intentionally absent;
	-- they only appear via the hazard-cluster mechanism below, which guarantees
	-- each one is paired with a working neutraliser before the safety backstop runs.
	local pool = {
		{ t = "Stone",   w = 6 }, { t = "Spring",  w = 3 }, { t = "Ice",     w = 3 },
		{ t = "Void",    w = 3 }, { t = "Crumble", w = 2 }, { t = "Phantom", w = 2 },
		{ t = "Beacon",  w = 1 }, { t = "Inverter", w = 1 },
		{ t = "Push",    w = 2 }, { t = "Warp",     w = 1 },   -- NEW: allowed on the safe path
	}

	-- Guaranteed-safe fillers for the gap cell inside 3-cell clusters.
	local safePool = {
		{ t = "Stone",  w = 6 }, { t = "Spring", w = 3 },
		{ t = "Ice",    w = 3 }, { t = "Void",   w = 2 },
	}

	-- Static 2-cell cluster definitions. Consecutive path[] cells are always exactly
	-- one grid step apart, so the Inverter in pairs 1 & 2 is guaranteed adjacent.
	-- build(grid, cs): cs[1] = first path cell, cs[2] = second path cell.
	local clusters2 = {
		-- Inverter → Shock: Inverter grounds the Shock via the Neutralizable flag.
		{ w = 3, build = function(g, cs)
			g[cs[1].x][cs[1].z].tile = "Inverter"; g[cs[1].x][cs[1].z].attr = {}
			g[cs[2].x][cs[2].z].tile = "Shock";    g[cs[2].x][cs[2].z].attr = {}
		end },
		-- Shock → Inverter: same pair in reverse order.
		{ w = 3, build = function(g, cs)
			g[cs[1].x][cs[1].z].tile = "Shock";    g[cs[1].x][cs[1].z].attr = {}
			g[cs[2].x][cs[2].z].tile = "Inverter"; g[cs[2].x][cs[2].z].attr = {}
		end },
		-- Beacon → Shock: Beacon deactivates the adjacent Shock via honourBeacons.
		{ w = 2, build = function(g, cs)
			local dir = dirBetween(cs[1], cs[2]) or "Up"
			g[cs[1].x][cs[1].z].tile = "Beacon"; g[cs[1].x][cs[1].z].attr = { PointDir = dir }
			g[cs[2].x][cs[2].z].tile = "Shock";  g[cs[2].x][cs[2].z].attr = {}
		end },
		-- Beacon → Lava: only a Beacon can neutralise Lava (Lava.Neutralizable = false).
		{ w = 2, build = function(g, cs)
			local dir = dirBetween(cs[1], cs[2]) or "Up"
			g[cs[1].x][cs[1].z].tile = "Beacon"; g[cs[1].x][cs[1].z].attr = { PointDir = dir }
			g[cs[2].x][cs[2].z].tile = "Lava";   g[cs[2].x][cs[2].z].attr = {}
		end },
	}

	local last, last2
	local cooldown = 0   -- remaining cells before a new cluster is allowed

	local i = 2
	while i <= n - 1 do
		local c = path[i]
		cooldown = math.max(0, cooldown - 1)
		local clusterPlaced = false

		-- ── Hazard-cluster attempt ────────────────────────────────────────────
		if cooldown == 0 and rng:NextNumber() < HAZARD_CLUSTER_CHANCE then
			local cands = {}

			-- 2-cell clusters: need i+1 to still be an interior cell (not the goal).
			if i + 1 <= n - 1 then
				for _, def in ipairs(clusters2) do
					table.insert(cands, { w = def.w, len = 2, build = def.build })
				end
			end

			-- 3-cell clusters: Beacon → safe filler → hazard.
			-- Only valid when all three consecutive cells share the same cardinal
			-- direction AND BeaconRange can bridge the 2-step gap to the hazard.
			if i + 2 <= n - 1 and TileRules.BeaconRange >= 2 then
				local a, b, cc = path[i], path[i + 1], path[i + 2]
				local d1, d2   = dirBetween(a, b), dirBetween(b, cc)
				if d1 and d1 == d2 then
					local dir = d1   -- capture for the two closures below
					-- Beacon →→ Shock
					table.insert(cands, { w = 1, len = 3, build = function(g, cs)
						g[cs[1].x][cs[1].z].tile = "Beacon"; g[cs[1].x][cs[1].z].attr = { PointDir = dir }
						-- cs[2] (gap cell) is filled after this builder returns
						g[cs[3].x][cs[3].z].tile = "Shock";  g[cs[3].x][cs[3].z].attr = {}
					end })
					-- Beacon →→ Lava
					table.insert(cands, { w = 1, len = 3, build = function(g, cs)
						g[cs[1].x][cs[1].z].tile = "Beacon"; g[cs[1].x][cs[1].z].attr = { PointDir = dir }
						g[cs[3].x][cs[3].z].tile = "Lava";   g[cs[3].x][cs[3].z].attr = {}
					end })
				end
			end

			if #cands > 0 then
				-- Weighted pick among candidates.
				local total = 0; for _, cd in ipairs(cands) do total += cd.w end
				local r, acc, chosen = rng:NextInteger(1, total), 0, nil
				for _, cd in ipairs(cands) do
					acc += cd.w
					if r <= acc and not chosen then chosen = cd end
				end

				if chosen then
					-- Gather the path-cell slice for this cluster.
					local cs = {}
					for k = 1, chosen.len do cs[k] = path[i + k - 1] end

					chosen.build(grid, cs)

					-- 3-cell builders leave the gap cell (cs[2]) unset; fill it safely.
					if chosen.len == 3 then
						local mid = cs[2]
						grid[mid.x][mid.z].tile = weightedPick(safePool, rng)
						grid[mid.x][mid.z].attr = {}
					end

					cooldown      = CLUSTER_COOLDOWN_CELLS
					last, last2   = nil, nil   -- reset run-duplicate guard after cluster
					i            += chosen.len
					clusterPlaced = true
				end
			end
		end

		if clusterPlaced then continue end

		-- ── Regular single-tile placement ─────────────────────────────────────
		local cell = grid[c.x][c.z]
		-- Decide a legal Push for THIS cell up front (nil if no shove lands on the path).
		local pushOpt = pickPushOption(grid, c, rng)
		local choice, guard = nil, 0
		repeat
			guard += 1
			choice = weightedPick(pool, rng)
			-- reject a Push that can't land on the path (blacklisted here -> re-roll),
			-- keep the original "no 3 identical in a row" guard.
			local badPush = (choice == "Push") and (pushOpt == nil)
			local triple  = (choice == last and last == last2)
		until (not badPush and not triple) or guard > 12
		if choice == "Push" and pushOpt == nil then choice = "Stone" end  -- guard expired: fall back

		cell.tile = choice
		cell.attr = {}
		if choice == "Phantom" then
			cell.attr.Underlying = "Stone"
		elseif choice == "Beacon" then
			cell.attr.PointDir = "Up"
		elseif choice == "Push" then
			cell.attr.PushDir   = pushOpt.dirWorld   -- fixed so the shove always hits a path tile
			cell.attr.PushPower = pushOpt.power
		end
		last2, last = last, choice
		i += 1
	end

	return startCell, goalCell
end

--========================= decorate everything off-path ====================--
local function decorate(grid, w, l, rng)
	local pool = {
		{ t = "Stone",  w = 1 }, { t = "Shock", w = 8 }, { t = "Lava",   w = 8 },
		{ t = "Spring", w = 1 }, { t = "Ice",   w = 3 }, { t = "Void",   w = 2 },
		{ t = "Crumble",w = 3 }, { t = "Phantom",w = 3 },{ t = "Beacon", w = 1 },
		{ t = "Inverter",w = 2 },{ t = "Warp",  w = 1 }, { t = "Push",   w = 3 },
	}
	for x = 1, w do
		for z = 1, l do
			local cell = grid[x][z]
			if not cell.onPath then
				local t = weightedPick(pool, rng)
				cell.tile = t
				cell.attr = {}
				if t == "Phantom" then
					cell.attr.Underlying = (rng:NextNumber() < 0.5) and "Shock" or "Stone"
				elseif t == "Beacon" then
					cell.attr.PointDir = randomDir(rng)
				end
			end
		end
	end
end

--========================= beacons (bounded to BeaconRange) ================--
-- A Beacon switches OFF every tile it reaches except Goal and Spawn — hazards, mechanics
-- (Push/Warp/Crumble/Spring/Ice/Void), Phantoms, and even other Inverters and Beacons.
-- Resolution is simultaneous: a Beacon still projects from its generated position even if
-- another Beacon has switched it off, so two beacons crossing each other both fire. A
-- deactivated Phantom keeps its hidden tile — it reveals on step but deals no damage. The
-- end-of-build safety backstop re-checks the route after this runs.
local function honourBeacons(grid, w, l)
	for x = 1, w do
		for z = 1, l do
			if grid[x][z].tile == "Beacon" then
				for _, t in ipairs(TileRules.beaconTargets(grid, x, z)) do
					local tc = grid[t.x][t.z]
					if tc.tile ~= "Goal" and tc.tile ~= "Spawn" then
						tc.attr.Deactivated = true
					end
				end
			end
		end
	end
end

--========================= public build ====================================--
function PathGenerator.build(width, length, seed)
	seed = seed or os.time()
	local rng = Random.new(seed)
	local grid = newGrid(width, length)
	local path = carvePath(width, length, rng)
	local startCell, goalCell = fillPath(grid, path, rng)
	decorate(grid, width, length, rng)
	honourBeacons(grid, width, length)   -- sets Deactivated on Beacon targets

	-- Backstop: any path cell still unsafe becomes Stone. Correctly-formed clusters
	-- always pass (Deactivated=true or adjacent Inverter found), so this only
	-- catches genuine edge cases, never the intentional hazard clusters.
	for _, c in ipairs(path) do
		if not TileRules.isCellSafe(grid, c.x, c.z) then
			grid[c.x][c.z].tile = "Stone"
			grid[c.x][c.z].attr = {}
			grid[c.x][c.z].onPath = true
		end
	end

	return {
		grid = grid, width = width, length = length,
		start = startCell, goal = goalCell, path = path, seed = seed,
	}
end

PathGenerator.Directions = Directions
return PathGenerator
