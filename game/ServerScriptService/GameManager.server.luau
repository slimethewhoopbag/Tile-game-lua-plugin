--!nonstrict
--[[ GameManager — ServerScriptService > GameManager (Script). REPLACES old one.

	Detection fix: tiles are detected by raycasting onto the COLLISION PAD (which this
	script creates at a known height under each player and tags with GridX/GridZ), not
	the cloned model's parts. The model's geometry no longer affects whether a step
	registers — this is what stops the new tiles from "doing nothing".

	Phantom: the underlying effect (e.g. electric) still triggers on step UNLESS the
	tile is neutralised. Neutralisation now lives in TileRules, so a Phantom hiding
	electric next to an Inverter is treated exactly like a real electric tile next to
	an Inverter — safe. This is the runtime half of the inconsistent-inversion fix.
]]

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local Shared        = ReplicatedStorage:WaitForChild("Shared")
local Config        = require(Shared:WaitForChild("Config"))
local TileRules     = require(Shared:WaitForChild("TileRules"))
local Modules       = ServerScriptService:WaitForChild("Modules")
local PathGenerator = require(Modules:WaitForChild("PathGenerator"))
local TilePlacer    = require(Modules:WaitForChild("TilePlacer"))
local TileDatabase  = require(Shared:WaitForChild("TileDatabase"))   -- NEW: Phantom reveal colour/material
local TileImages    = require(Shared:WaitForChild("TileImages"))     -- NEW: Phantom reveal texture

local SP = Enum.Material.SmoothPlastic   -- NEW: Phantom reveal material rule

--========================= remotes =========================--
local function ensureRemotes()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then folder = Instance.new("Folder"); folder.Name = "Remotes"; folder.Parent = ReplicatedStorage end
	local function ev(name)
		local e = folder:FindFirstChild(name)
		if not e then e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = folder end
		return e
	end
	return { TileStepped = ev("TileStepped"), ClientEffect = ev("ClientEffect") }
end
local Remotes = ensureRemotes()

--========================= state =========================--
local currentLevel, tileRefs, gridContainer, layout
local playerTile = {}
local comboCount = {}
local comboSeen  = {}

local PUSH_VECTORS = { Right=Vector3.new(1,0,0), Left=Vector3.new(-1,0,0), Forward=Vector3.new(0,0,1), Back=Vector3.new(0,0,-1) }

--========================= helpers =========================--
local function tileWorldCenter(x, z)
	return Vector3.new(layout.originX + (x-1)*layout.pitchX, layout.standY, layout.originZ + (z-1)*layout.pitchZ)
end

-- the grid cell a player is currently standing on, parsed from the stored "x_z" key
local function cellOf(plr)
	local s = playerTile[plr]
	local sx, sz = s and string.match(s, "^(%d+)_(%d+)$"), nil
	if not sx then return nil, nil end
	return tonumber(sx), tonumber(sz)
end

-- Crumble: drop the WHOLE model as one rigid piece (no damage), then snap it back.
local function dropTile(x, z, secs)
	local model = tileRefs and tileRefs[x] and tileRefs[x][z]
	if not model then return end
	if model:GetAttribute("Dropping") then return end
	model:SetAttribute("Dropping", true)

	local prim = model.PrimaryPart or model:FindFirstChild("ColorTile")
	local home, welds = {}, {}

	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then home[p] = p.CFrame end   -- remember where it belongs
	end

	-- weld everything to the primary so it falls in one piece, not as loose parts
	if prim then
		for p in pairs(home) do
			if p ~= prim then
				local wc = Instance.new("WeldConstraint")
				wc.Part0, wc.Part1 = prim, p
				wc.Parent = prim
				welds[#welds + 1] = wc
			end
		end
	end

	for p in pairs(home) do p.Anchored = false end          -- gravity takes over

	task.delay(secs or 8, function()
		for _, wc in ipairs(welds) do if wc.Parent then wc:Destroy() end end
		for p, cf in pairs(home) do
			if p.Parent then
				p.Anchored = true
				p.AssemblyLinearVelocity = Vector3.zero
				p.AssemblyAngularVelocity = Vector3.zero
				p.CFrame = cf
			end
		end
		model:SetAttribute("Dropping", false)
	end)
end

-- single source of truth: an Inverter (or any neutraliser) is next door
local function isInverterAdj(x, z)
	return TileRules.hasAdjacentNeutralizer(currentLevel.grid, x, z)
end

local function comboToSound(c)
	if c <= 4 then return c elseif c <= 7 then return 5 else return 6 end
end

--========================= tile effects (inlined) =========================--
local function flash(plr, color) Remotes.ClientEffect:FireClient(plr, "Flash", color) end

local function damage(plr, reason)
	local lives = (plr:GetAttribute("Lives") or Config.Round.Lives) - 1
	plr:SetAttribute("Lives", lives)
	flash(plr, Color3.fromRGB(220, 40, 40))
	local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.Health = 0 end
	print(string.format("[CURRENT] %s lost a life (%s). Lives: %d", plr.Name, reason, lives))
	if lives <= 0 then plr:SetAttribute("Lives", Config.Round.Lives) end -- TODO: elimination
end

local function playersNear(center, radius)
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - center).Magnitude <= radius then table.insert(out, p) end
	end
	return out
end

-- DEBUG: paint a tile's Base green to mark the safe path as it's walked.
local function paintBase(x, z)
	local model = tileRefs and tileRefs[x] and tileRefs[x][z]
	local baseP = model and model:FindFirstChild("Base")
	if baseP and baseP:IsA("BasePart") then
		baseP.Color = Config.Debug.PathColor
	end
end

-- Permanently unmask a Phantom: its top tile takes the colour, material and symbol of
-- whatever it was hiding (Lava, Shock, …). Server-side so all clients see it; latched
-- once via cell.attr.Revealed.
local function revealPhantom(x, z)
	local cell = currentLevel.grid[x][z]
	if cell.tile ~= "Phantom" or cell.attr.Revealed then return end
	cell.attr.Revealed = true

	local model = tileRefs and tileRefs[x] and tileRefs[x][z]
	local colorTile = model and model:FindFirstChild("ColorTile")
	if not colorTile then return end

	local under = cell.attr.Underlying or "Stone"
	local udef  = TileDatabase.get(under)
	colorTile.Color = udef.Color

	if udef.Material and udef.Material ~= SP then colorTile.Material = udef.Material end   -- only non-default material survives

	for _, d in ipairs(colorTile:GetChildren()) do                     -- drop the Phantom symbol
		if d:IsA("Decal") and d.Face == Enum.NormalId.Top then d:Destroy() end
	end
	local imgId = TileImages.get(under)
	if imgId and imgId ~= "" then                                      -- add the hidden tile's symbol
		local decal = Instance.new("Decal")
		decal.Face = Enum.NormalId.Top; decal.Texture = imgId; decal.Parent = colorTile
	end
	model:SetAttribute("Revealed", true)
end

-- Reveal a tile: apply its TRUE visuals (server, replicated) FIRST, then tell clients to
-- puff its fog away. Once-only per tile via cell.attr.FogRevealed.
local function revealTile(x, z)
	if not (currentLevel and tileRefs) then return end
	local col = currentLevel.grid[x]
	local cell = col and col[z]
	if not cell or cell.attr.FogRevealed then return end
	cell.attr.FogRevealed = true
	local model = tileRefs[x] and tileRefs[x][z]
	if not model then return end
	TilePlacer.applyVisuals(currentLevel, x, z, model)   -- true visuals first
	Remotes.ClientEffect:FireAllClients("Puff", x, z)     -- then clients clear the fog (with the puff)
end

-- Reveal an NxN box in expanding rings: centre now, outer rings after RingDelay each.
local function revealArea(cx, cz, radius)
	radius = radius or (Config.Fog.Radius or 2)
	revealTile(cx, cz)
	for r = 1, radius do
		task.delay(r * (Config.Fog.RingDelay or 0.06), function()
			if not currentLevel then return end
			for dx = -r, r do
				for dz = -r, r do
					if math.max(math.abs(dx), math.abs(dz)) == r then
						revealTile(cx + dx, cz + dz)
					end
				end
			end
		end)
	end
end

local function handleStep(plr, x, z)
	local cell = currentLevel.grid[x][z]
	local t = cell.tile

	-- A tile switched off by a beacon does nothing. A deactivated Phantom still reveals
	-- what it was hiding, but deals no damage. Goal and Spawn are never deactivated.
	if cell.attr.Deactivated then
		if t == "Phantom" then revealPhantom(x, z) end
		return
	end

	if t == "Goal" then
		if not plr:GetAttribute("Won") then
			plr:SetAttribute("Won", true)
			flash(plr, Color3.fromRGB(60, 220, 90))
			print(string.format("[CURRENT] %s reached the GOAL!", plr.Name))
		end

	elseif t == "Shock" then
		if not TileRules.isCellSafe(currentLevel.grid, x, z) then
			for _, p in ipairs(playersNear(tileWorldCenter(x, z), Config.Shock.AoeRadius)) do
				if not p:GetAttribute("Sliding") then            -- mid-push players are invulnerable
					local px, pz = cellOf(p)
					if not (px and TileRules.isGrounded(currentLevel.grid, px, pz)) then
						damage(p, "Shock")
					end
				end
			end
		end

	elseif t == "Lava" then
		-- a Beacon can switch Lava off; respect that like every other hazard
		if not TileRules.isCellSafe(currentLevel.grid, x, z) then
			damage(plr, "Lava")
		end

	elseif t == "Phantom" then
		revealPhantom(x, z)   -- permanently show what it was hiding (colour + texture)
		if not TileRules.isCellSafe(currentLevel.grid, x, z) then
			damage(plr, "Phantom")
		end

	elseif t == "Crumble" then
		local k = x .. "_" .. z
		task.delay(Config.Crumble.Delay, function()
			if playerTile[plr] == k then
				dropTile(x, z, Config.Crumble.DropTime or 8)   -- drops the tile; never takes a life
			end
		end)

	elseif t == "Warp" then
		local link = cell.attr.WarpTo
		if link and (plr:GetAttribute("WarpLock") or 0) <= os.clock() then
			plr:SetAttribute("WarpLock", os.clock() + (Config.Warp.Lock or 0.6))
			local char = plr.Character
			if char then
				char:PivotTo(CFrame.new(tileWorldCenter(link.x, link.z) + Vector3.new(0, 3, 0)))
				playerTile[plr] = link.x .. "_" .. link.z
			end
			if Config.Fog.Enabled then revealArea(link.x, link.z) end   -- reveal the destination on teleport
		end

	elseif t == "Push" then
		if (plr:GetAttribute("PushCD") or 0) <= os.clock() then
			plr:SetAttribute("PushCD", os.clock() + Config.Push.Cooldown)
			local model   = tileRefs[x] and tileRefs[x][z]
			local dirName = (model and model:GetAttribute("PushDir")) or "Forward"
			local power   = (model and model:GetAttribute("PushPower")) or 1
			local dv = PUSH_VECTORS[dirName] or PUSH_VECTORS.Forward
			local tx = math.clamp(x + dv.X * power, 1, currentLevel.width)
			local tz = math.clamp(z + dv.Z * power, 1, currentLevel.length)
			local dur = math.clamp(power * Config.Push.SlidePerTile, Config.Push.MinTime, Config.Push.MaxTime)


			if Config.Fog.Enabled then revealArea(tx, tz) end   -- reveal the destination now, not after the slide
			-- INVULNERABLE SLIDE: while "Sliding" is set the detection loop skips this player
			-- entirely, so NO tile between origin and target can fire. This is what stops a
			-- lava tile in the slide path from killing them mid-push.

			plr:SetAttribute("Sliding", true)
			Remotes.ClientEffect:FireClient(plr, "Push", tileWorldCenter(tx, tz), dur)

			task.delay(dur + (Config.Push.LandBuffer or 0.15), function()
				if not (currentLevel and tileRefs) then
					plr:SetAttribute("Sliding", false); playerTile[plr] = nil; return
				end
				-- Snap to the target COLUMN (keep height & facing) so the next scan reads the
				-- target tile, not one we only slid across. Clearing playerTile makes the next
				-- scan register the target as a fresh step, firing ONLY that tile (the single
				-- "touch" the push is meant to deliver).
				local char = plr.Character
				local hrp  = char and char:FindFirstChild("HumanoidRootPart")
				if hrp then
					local c = tileWorldCenter(tx, tz)
					hrp.CFrame = CFrame.new(c.X, hrp.Position.Y, c.Z) * hrp.CFrame.Rotation
					hrp.AssemblyLinearVelocity = Vector3.zero
				end
				playerTile[plr] = nil
				plr:SetAttribute("Sliding", false)
			end)
		end
	end
end

--========================= build =========================--
local function clearGrid()
	if gridContainer then gridContainer:Destroy() gridContainer = nil end
	tileRefs, currentLevel = nil, nil
end

local function spawnFrame()
	-- gray spawn platform geometry: behind the grid, centred on its width
	local cfg    = Config.Spawn or {}
	local depth  = cfg.PlatformDepth or 28
	local wTiles = cfg.PlatformWidthTiles or 20
	local gap    = cfg.GapBehind or 0
	local W = currentLevel.width
	local cX = layout.originX + (W - 1) * layout.pitchX / 2
	local frontEdgeZ = layout.originZ - layout.pitchZ / 2     -- front face of row z = 1
	local centerZ = frontEdgeZ - gap - depth / 2
	return { cX = cX, centerZ = centerZ, sizeX = wTiles * layout.pitchX, depth = depth, topY = layout.standY }
end

local function positionSpawn()
	local sp = workspace:FindFirstChild("CurrentSpawn")
	if not sp then
		sp = Instance.new("SpawnLocation")
		sp.Name="CurrentSpawn"; sp.Anchored=true; sp.CanCollide=false; sp.CanQuery=false
		sp.Transparency=1; sp.Size=Vector3.new(6,1,6); sp.Neutral=true; sp.Parent=workspace
	end
	-- stand on the platform behind the grid, centred, facing the grid (+Z).
	-- If players spawn facing away, swap the target to (0, 0, -1).
	local sf  = spawnFrame()
	local pos = Vector3.new(sf.cX, sf.topY + 1.5, sf.centerZ)
	sp.CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1))
end

local function linkWarps()
	local warps = {}
	for x=1,currentLevel.width do for z=1,currentLevel.length do
			if currentLevel.grid[x][z].tile == "Warp" then table.insert(warps, {x=x,z=z}) end
		end end
	local rng = Random.new((currentLevel.seed or 1) + 999)
	for i=#warps,2,-1 do local j=rng:NextInteger(1,i); warps[i],warps[j]=warps[j],warps[i] end
	local i = 1
	while i + 1 <= #warps do
		local a, b = warps[i], warps[i+1]
		currentLevel.grid[a.x][a.z].attr.WarpTo = {x=b.x, z=b.z}
		currentLevel.grid[b.x][b.z].attr.WarpTo = {x=a.x, z=a.z}
		i += 2
	end
	if i == #warps and #warps >= 3 then
		local odd = warps[#warps]
		local target = warps[rng:NextInteger(1, #warps - 1)]
		currentLevel.grid[odd.x][odd.z].attr.WarpTo = {x=target.x, z=target.z}
	end
end

local function buildArena()
	local standY = layout.standY
	for x=1,currentLevel.width do
		for z=1,currentLevel.length do
			local cell   = currentLevel.grid[x][z]
			local model  = tileRefs[x][z]
			local center = tileWorldCenter(x, z)

			-- the player stands on this; it is also the detection surface
			local col = Instance.new("Part")
			col.Name="Collision"; col.Anchored=true; col.CanCollide=true; col.CanQuery=true; col.Transparency=1; col.CastShadow=false
			col.Size = Vector3.new(layout.pitchX, 0.4, layout.pitchZ)   -- edge-to-edge, no seams, one cell each
			col.Position = Vector3.new(center.X, standY - 0.2, center.Z)
			col:SetAttribute("GridX", x); col:SetAttribute("GridZ", z); col:SetAttribute("TileType", cell.tile)
			-- Read by the client heartbeat for Spring height and the Void tint. "Inverted"
			-- already excludes deactivated inverters (see TileRules.hasAdjacentNeutralizer).
			col:SetAttribute("Inverted", isInverterAdj(x, z))
			col:SetAttribute("Deactivated", cell.attr.Deactivated == true)
			if cell.tile == "Ice" and not cell.attr.Deactivated then
				local fr = isInverterAdj(x,z) and Config.Ice.GrippyFriction or Config.Ice.Friction
				col.CustomPhysicalProperties = PhysicalProperties.new(0.7, fr, 0, Config.Ice.Weight, 1)
			end
			col.Parent = model
		end
	end

	local W, L = currentLevel.width, currentLevel.length
	local sizeX, sizeZ = W*layout.pitchX, L*layout.pitchZ
	local minX = layout.originX - layout.pitchX/2
	local minZ = layout.originZ - layout.pitchZ/2
	local cX = layout.originX + (W-1)*layout.pitchX/2
	local cZ = layout.originZ + (L-1)*layout.pitchZ/2
	local h = 30
	local function wall(wx, wz, sx, sz)
		local w = Instance.new("Part"); w.Anchored=true; w.CanCollide=true; w.CanQuery=false; w.Transparency=1; w.CastShadow=false
		w.Size=Vector3.new(sx,h,sz); w.Position=Vector3.new(wx, standY+h/2-0.5, wz); w.Parent=gridContainer
	end
	-- gray spawn platform behind the grid (one part); players spawn here, not on a tile
	local sf = spawnFrame()
	local plat = Instance.new("Part")
	plat.Name = "SpawnPlatform"
	plat.Anchored = true; plat.CanCollide = true; plat.CanQuery = false; plat.CastShadow = false
	plat.Material = Enum.Material.SmoothPlastic
	plat.Color = (Config.Spawn and Config.Spawn.Color) or Color3.fromRGB(105, 105, 110)
	plat.Size = Vector3.new(sf.sizeX, 1, sf.depth)
	plat.Position = Vector3.new(sf.cX, sf.topY - 0.5, sf.centerZ)
	plat.Parent = gridContainer

	 wall(cX, minZ+sizeZ+0.5, sizeX+4, 1)
	wall(minX-0.5, cZ, 1, sizeZ+4); wall(minX+sizeX+0.5, cZ, 1, sizeZ+4)
end

local function buildBoard(seed)
	clearGrid()
	comboCount, comboSeen = {}, {}
	seed = seed or (os.time() + math.random(1, 100000))
	currentLevel = PathGenerator.build(Config.Grid.Width, Config.Grid.Length, seed)
	gridContainer, tileRefs, layout = TilePlacer.build(currentLevel, { Parent = workspace })
	linkWarps(); buildArena(); positionSpawn()
	print(string.format("[CURRENT] Board built. seed=%d start=(%d,%d) goal=(%d,%d)",
		seed, currentLevel.start.x, currentLevel.start.z, currentLevel.goal.x, currentLevel.goal.z))
end

--========================= authoritative detection =========================--
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local accum = 0
RunService.Heartbeat:Connect(function(dt)
	accum += dt
	if accum < Config.Round.ScanRate then return end
	accum = 0
	if not currentLevel then return end

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr:GetAttribute("Sliding") then continue end
		local char = plr.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		local hum  = char and char:FindFirstChildOfClass("Humanoid")
		if not (hrp and hum and hum.Health > 0) then continue end

		if hum.FloorMaterial == Enum.Material.Air then
			playerTile[plr] = nil
			continue
		end

		rayParams.FilterDescendantsInstances = { char }
		local res  = workspace:Raycast(hrp.Position, Vector3.new(0, -10, 0), rayParams)
		local base = res and res.Instance
		local gx = base and base:GetAttribute("GridX")
		local gz = base and base:GetAttribute("GridZ")
		if gx and gz then
			local k = gx .. "_" .. gz
			if playerTile[plr] ~= k then
				playerTile[plr] = k
				local model = tileRefs[gx] and tileRefs[gx][gz]
				if model then Remotes.TileStepped:FireAllClients(model) end

				handleStep(plr, gx, gz)
				if Config.Fog.Enabled then revealArea(gx, gz) end   -- server-driven fog/visual reveal


				local cell = currentLevel.grid[gx][gz]
				-- Void tint and Spring height are driven entirely client-side from the
				-- collision pad's attributes (see TileVisualsClient); no per-step event needed.
				if Config.Debug.ShowSafePath and Config.Debug.PaintMode == "Touch" and cell.onPath then
					paintBase(gx, gz)
				end
				if cell.tile ~= "Spawn" then
					if cell.onPath then
						comboSeen[plr] = comboSeen[plr] or {}
						if not comboSeen[plr][k] then
							comboSeen[plr][k] = true
							local c = (comboCount[plr] or 0) + 1
							comboCount[plr] = c
							Remotes.ClientEffect:FireClient(plr, "Combo", comboToSound(c))
						end
					else
						comboCount[plr] = 0
					end
				end
			end
		end
	end
end)

--========================= lifecycle =========================--
local function setupPlayer(plr)
	plr:SetAttribute("Lives", Config.Round.Lives)
	plr:SetAttribute("Won", false)
	plr.CharacterAdded:Connect(function()
		playerTile[plr] = nil; comboCount[plr] = 0; comboSeen[plr] = {}
	end)
end
Players.PlayerAdded:Connect(setupPlayer)
for _, p in ipairs(Players:GetPlayers()) do setupPlayer(p) end
Players.PlayerRemoving:Connect(function(plr) playerTile[plr]=nil; comboCount[plr]=nil; comboSeen[plr]=nil end)

buildBoard()
_G.CurrentRebuild = buildBoard

-- ============================ DEBUG: safe-path view ============================
-- Flip how the guaranteed-safe path is shown and apply it to the LIVE board:
--   "All"   -> whole path painted green immediately
--   "Touch" -> each path tile lights green only when a player steps on it (default)
--   "Off"   -> Base parts left at template colour, nothing painted
-- Run from the command bar, e.g.   _G.SetPathDebug("All")
function _G.SetPathDebug(mode)
	if mode ~= "All" and mode ~= "Touch" and mode ~= "Off" then
		warn('[CURRENT] SetPathDebug expects "All", "Touch" or "Off"'); return
	end
	Config.Debug.ShowSafePath = (mode ~= "Off")
	Config.Debug.PaintMode    = (mode == "Off") and "Touch" or mode
	if not (currentLevel and tileRefs) then return end

	local tilesFolder = ReplicatedStorage:FindFirstChild("Tiles")
	local template    = tilesFolder and tilesFolder:FindFirstChild("BasicTile")
	local defBase     = template and template:FindFirstChild("Base")
	local defColor    = (defBase and defBase.Color) or Color3.fromRGB(120, 124, 130)

	for x = 1, currentLevel.width do
		for z = 1, currentLevel.length do
			local model = tileRefs[x][z]
			local baseP = model and model:FindFirstChild("Base")
			if baseP and baseP:IsA("BasePart") then
				if mode == "All" and currentLevel.grid[x][z].onPath then
					baseP.Color = Config.Debug.PathColor
				else
					baseP.Color = defColor   -- Touch re-lights on step; Off stays default
				end
			end
		end
	end
end
