--!nonstrict
--[[ TilePlacer — ServerScriptService > Modules > TilePlacer (ModuleScript). REPLACES old one.

	Tiles are CLONED with their default template look only. A tile's true visuals
	(colour, material, symbol, arrows, ring blend) are applied by TilePlacer.applyVisuals,
	which runs only when the tile is REVEALED (front rows at build; everything else via
	GameManager.revealTile at runtime). Hidden-by-fog tiles therefore stay generic until
	discovered. Detection still happens on GameManager's collision pad (parts CanQuery=false).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config       = require(Shared:WaitForChild("Config"))
local TileDatabase = require(Shared:WaitForChild("TileDatabase"))
local TileImages   = require(Shared:WaitForChild("TileImages"))
local TileRules    = require(Shared:WaitForChild("TileRules"))

local TilePlacer = {}
local SP = Enum.Material.SmoothPlastic
local GRID_TO_PUSH = { Up="Forward", Down="Back", Left="Left", Right="Right" }

local ARROW_BASE = 0
local PUSHDIR_ROTATION = { Back = 90, Right = 180, Forward = 270, Left = 0 }
local function arrowAngle(pushDir)
	return ((PUSHDIR_ROTATION[pushDir] or 0) + ARROW_BASE) % 360
end

local function getTemplate()
	local tiles = ReplicatedStorage:FindFirstChild("Tiles")
	return tiles and tiles:FindFirstChild("BasicTile")
end

-- single source of truth: an Inverter (or any neutraliser) is next door
local function adjacentToInverter(level, x, z)
	return TileRules.hasAdjacentNeutralizer(level.grid, x, z)
end

local function blend(colors)
	if #colors == 0 then return nil end
	if #colors == 1 then return colors[1] end
	local r, g, b = 0, 0, 0
	for _, c in ipairs(colors) do r += c.R; g += c.G; b += c.B end
	local n = #colors
	return Color3.new(r/n, g/n, b/n)
end

local function computeAffectors(level)
	local aff = {}
	for x=1,level.width do aff[x]={} for z=1,level.length do aff[x][z]={} end end
	local function mark(x, z, typ)
		if level.grid[x] and level.grid[x][z] then aff[x][z][typ] = true end
	end
	for x=1,level.width do
		for z=1,level.length do
			local cell = level.grid[x][z]
			if cell.tile == "Inverter" then
				mark(x+1,z,"Inverter"); mark(x-1,z,"Inverter"); mark(x,z+1,"Inverter"); mark(x,z-1,"Inverter")
			elseif cell.tile == "Beacon" then
				for _, t in ipairs(TileRules.beaconTargets(level.grid, x, z)) do
					mark(t.x, t.z, "Beacon")
				end
			end
		end
	end
	return aff
end

local function makeArrowGui(colorTile, name, angle, count, imageId)
	imageId = imageId or TileImages.PushArrow
	if not imageId or imageId == "" then return end
	-- avoid stacking if visuals somehow re-apply
	local existing = colorTile:FindFirstChild(name)
	if existing then existing:Destroy() end
	local gui = Instance.new("SurfaceGui")
	gui.Name = name; gui.Face = Enum.NormalId.Top; gui.Adornee = colorTile
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize; gui.CanvasSize = Vector2.new(200, 200)
	gui.Parent = colorTile
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6); layout.Parent = gui
	for i = 1, count do
		local slot = Instance.new("Frame")
		slot.BackgroundTransparency = 1
		slot.Size = UDim2.fromOffset(60, 60)
		slot.LayoutOrder = i
		slot.Parent = gui

		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(1, 1)
		img.Image = imageId
		img.Rotation = angle
		img.Parent = slot
	end
end

-- Apply a tile's TRUE visuals. Runs ONLY when the tile is revealed; hidden tiles keep
-- the template default. Guarded so it applies once. Reads level.affectors (set in build)
-- and the Push/Beacon direction attributes (set in build).
function TilePlacer.applyVisuals(level, x, z, model)
	if not model or model:GetAttribute("VisualsApplied") then return end
	model:SetAttribute("VisualsApplied", true)

	local cell = level.grid[x][z]
	local def  = TileDatabase.get(cell.tile)
	local colorTile = model:FindFirstChild("ColorTile")
	local outerRing = model:FindFirstChild("OuterRing")
	local baseP     = model:FindFirstChild("Base")

	if colorTile then
		colorTile.Color = def.Color
		if def.Material and def.Material ~= SP then colorTile.Material = def.Material end
	end

	if outerRing and level.affectors and level.affectors[x] and level.affectors[x][z] then
		local colors = {}
		for typ in pairs(level.affectors[x][z]) do table.insert(colors, TileDatabase.get(typ).Color) end
		local mix = blend(colors)
		if mix then outerRing.Color = mix end
	end

	if baseP and Config.Debug.ShowSafePath and Config.Debug.PaintMode == "All" and cell.onPath then
		baseP.Color = Config.Debug.PathColor
	end

	if cell.tile == "Push" then
		if colorTile then
			local dirWorld = model:GetAttribute("PushDir") or "Forward"
			local power    = model:GetAttribute("PushPower") or 1
			makeArrowGui(colorTile, "PushArrows", arrowAngle(dirWorld), power, TileImages.PushArrow)
		end

	elseif cell.tile == "Beacon" then
		if colorTile then
			local dirName = cell.attr.PointDir or "Up"
			makeArrowGui(colorTile, "BeaconArrow", arrowAngle(GRID_TO_PUSH[dirName] or "Forward"), 1, TileImages.Beacon or TileImages.PushArrow)
		end

	elseif colorTile then
		-- Phantom: shows underlying COLOUR if stepped (Revealed) or grounded by an adjacent
		-- Inverter. The symbol only becomes the underlying's once actually STEPPED — next to
		-- an Inverter it keeps the Phantom symbol (preserves the original behaviour).
		local symbolType = cell.tile
		if cell.tile == "Phantom" then
			local stepped     = cell.attr.Revealed == true
			local inverterAdj = adjacentToInverter(level, x, z)
			if stepped or inverterAdj then
				local udef = TileDatabase.get(cell.attr.Underlying or "Stone")
				colorTile.Color = udef.Color
				if udef.Material and udef.Material ~= SP then colorTile.Material = udef.Material end
				if stepped then symbolType = cell.attr.Underlying or "Stone" end
			end
		end
		-- symbol on top (clear existing first so re-applies never stack)
		for _, d in ipairs(colorTile:GetChildren()) do
			if d:IsA("Decal") and d.Face == Enum.NormalId.Top then d:Destroy() end
		end
		local imgId = TileImages.get(symbolType)
		if imgId and imgId ~= "" then
			local decal = Instance.new("Decal"); decal.Face = Enum.NormalId.Top; decal.Texture = imgId; decal.Parent = colorTile
		end
	end
end

function TilePlacer.build(level, opts)
	opts = opts or {}
	local parent = opts.Parent or workspace
	local template = getTemplate()
	assert(template and template.PrimaryPart, "ReplicatedStorage.Tiles.BasicTile (with a PrimaryPart) is required")

	local g = Config.Grid
	local psize  = template.PrimaryPart.Size
	local pitchX = psize.X + g.Gap
	local pitchZ = psize.Z + g.Gap
	local standY = g.Origin.Y
	local primCenterY = standY - psize.Y / 2

	level.affectors = computeAffectors(level)   -- stored so applyVisuals can use it at reveal
	local container = Instance.new("Folder"); container.Name = "CurrentGrid"
	local tileRefs = {}
	local rng = Random.new((level.seed or 1) + 777)

	local fogOn     = Config.Fog and Config.Fog.Enabled
	local frontRows = (Config.Fog and Config.Fog.FrontRows) or 0

	for x = 1, level.width do
		tileRefs[x] = {}
		for z = 1, level.length do
			local cell = level.grid[x][z]
			local cx = g.Origin.X + (x-1)*pitchX
			local cz = g.Origin.Z + (z-1)*pitchZ

			local model = template:Clone()
			model.Name = string.format("Tile_%d_%d", x, z)

			-- visuals only: static, non-colliding, NON-queryable (detection is on the pad)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true; d.CanCollide = false; d.CanQuery = false
				end
			end
			model:SetAttribute("TileType", cell.tile)
			if cell.attr.PointDir then model:SetAttribute("PointDir", cell.attr.PointDir) end

			-- Push direction/power decided at build (deterministic). The ARROW is drawn later,
			-- in applyVisuals, so it only shows once the tile is revealed.
			if cell.tile == "Push" then
				local dirWorld, power
				if cell.attr.PushDir and cell.attr.PushPower then
					dirWorld, power = cell.attr.PushDir, cell.attr.PushPower
				else
					local optsdir = {}
					if x < level.width then table.insert(optsdir, {dir="Right",   max=level.width-x}) end
					if x > 1            then table.insert(optsdir, {dir="Left",    max=x-1}) end
					if z < level.length then table.insert(optsdir, {dir="Forward", max=level.length-z}) end
					if z > 1            then table.insert(optsdir, {dir="Back",    max=z-1}) end
					local pick = optsdir[rng:NextInteger(1, #optsdir)]
					dirWorld, power = pick.dir, math.min(rng:NextInteger(1, 3), pick.max)
				end
				model:SetAttribute("PushDir", dirWorld)
				model:SetAttribute("PushPower", power)
			end

			model:PivotTo(CFrame.new(cx, primCenterY, cz))

			-- Fog: opaque until revealed; NEVER collidable. Hidden tiles stay at the template
			-- default (no colours/symbols/arrows) until reveal applies their true visuals.
			local fog = model:FindFirstChild("Fog")
			if fog and fog:IsA("BasePart") then fog.CanCollide = false end

			local revealedAtBuild = (not fogOn) or (z <= frontRows)
			if revealedAtBuild then
				cell.attr.FogRevealed = true
				if fog and fog:IsA("BasePart") then fog.Transparency = 1 end
				TilePlacer.applyVisuals(level, x, z, model)
			elseif fog and fog:IsA("BasePart") then
				fog.Transparency = 0
			end

			model.Parent = container
			tileRefs[x][z] = model
		end
	end

	container.Parent = parent
	local layout = { pitchX = pitchX, pitchZ = pitchZ, standY = standY, originX = g.Origin.X, originZ = g.Origin.Z }
	return container, tileRefs, layout
end

return TilePlacer
