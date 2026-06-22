--!nonstrict
--[[ TileVisualsClient — StarterPlayer > StarterPlayerScripts > TileVisualsClient (LocalScript).
	 Spring-bleed fix: JumpHeight driven locally from the tile underfoot.
	 Fog: the SERVER applies a tile's true visuals and marks it revealed, then sends a
	 "Puff" ClientEffect per tile. This script only ANIMATES the puff and clears that
	 tile's fog locally — it no longer computes reveal areas or applies tile visuals.
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Config          = require(Shared:WaitForChild("Config"))
local ScreenEffects   = require(Shared:WaitForChild("ScreenEffects"))
local SoundController = require(Shared:WaitForChild("SoundController"))

local Remotes      = ReplicatedStorage:WaitForChild("Remotes")
local TileStepped  = Remotes:WaitForChild("TileStepped")
local ClientEffect = Remotes:WaitForChild("ClientEffect")

ScreenEffects.init()

------------------------------------------------------------------------
-- Jump-height heartbeat (spring-bleed fix)
------------------------------------------------------------------------
local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Exclude

local lastTile = nil

local function tileUnder(char, hrp)
	rp.FilterDescendantsInstances = { char }
	local res  = workspace:Raycast(hrp.Position, Vector3.new(0, -10, 0), rp)
	local inst = res and res.Instance
	if not inst then return nil, false end
	return inst:GetAttribute("TileType"), inst:GetAttribute("Inverted") or false
end

RunService.Heartbeat:Connect(function()
	local char = player.Character
	if not char then lastTile = nil; return end

	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not (hum and hrp) then return end

	hum.UseJumpPower = false   -- remove this line if your game uses JumpPower

	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	local tile, inverted
	if grounded then
		tile, inverted = tileUnder(char, hrp)
	else
		tile, inverted = nil, false
	end

	if tile == "Spring" then
		hum.JumpHeight = inverted and Config.Spring.Low or Config.Spring.High
	else
		hum.JumpHeight = Config.Spring.Default
	end

	if tile and tile ~= lastTile then
		lastTile = tile
	elseif not tile then
		lastTile = nil
	end
end)

------------------------------------------------------------------------
-- Fog puff (visuals are applied server-side; we only animate + clear locally)
------------------------------------------------------------------------
local function tileAt(x, z)
	local folder = Workspace:FindFirstChild("CurrentGrid")
	return folder and folder:FindFirstChild(string.format("Tile_%d_%d", x, z))
end

local function puffFogTile(x, z)
	local model = tileAt(x, z)
	local fog = model and model:FindFirstChild("Fog")
	if not (fog and fog:IsA("BasePart")) then return end
	fog.CanCollide = false                          -- safety: fog never collides
	if fog.Transparency >= 1 then return end         -- already cleared here

	local puff = fog:Clone()
	puff:ClearAllChildren()
	puff.Name="FogPuff"; puff.Anchored=true; puff.CanCollide=false; puff.CanQuery=false; puff.CastShadow=false
	puff.CFrame = fog.CFrame + Vector3.new(0, 0.05, 0)
	puff.Parent = Workspace

	local s    = fog.Size
	local goal = Vector3.new(s.X * Config.Fog.PulseScale, s.Y, s.Z * Config.Fog.PulseScale)
	local tw   = TweenService:Create(
		puff,
		TweenInfo.new(Config.Fog.FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = goal, Transparency = 1 }
	)
	tw.Completed:Once(function() puff:Destroy() end)
	tw:Play()

	fog.Transparency = 1   -- reveal the (already server-coloured) tile underneath
end

------------------------------------------------------------------------
-- Push slide
------------------------------------------------------------------------
local function doPushSlide(targetPos, duration)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local goal = Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z)
	TweenService:Create(
		hrp,
		TweenInfo.new(duration or Config.Push.SlideTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = CFrame.new(goal) * hrp.CFrame.Rotation }
	):Play()
end

------------------------------------------------------------------------
-- Server event handler
------------------------------------------------------------------------
ClientEffect.OnClientEvent:Connect(function(kind, a, b)
	if kind == "Flash" then
		ScreenEffects.flash(a)
	elseif kind == "Combo" then
		SoundController.playCombo(a)
	elseif kind == "Push" then
		doPushSlide(a, b)
	elseif kind == "Puff" then
		if Config.Fog.Enabled then puffFogTile(a, b) end
	elseif kind == "Tile" then
		local tileType, inverted = a, b
		ScreenEffects.setVoid((tileType == "Void") and (inverted and "light" or "dark") or "none")
	end
end)

------------------------------------------------------------------------
-- Client-side ColorTile pulse on TileStepped (fog is handled by Puff, above)
------------------------------------------------------------------------
local function pulse(model)
	if not model then return end
	local ct = model:FindFirstChild("ColorTile")
	if not ct or not ct:IsA("BasePart") then return end

	local fx = ct:Clone()
	fx:ClearAllChildren()
	fx.Name        = "PulseFx"
	fx.Anchored    = true
	fx.CanCollide  = false
	fx.CanQuery    = false
	fx.CastShadow  = false
	fx.Color        = ct.Color
	fx.Material     = ct.Material
	fx.Transparency = math.min(ct.Transparency, 0.15)
	fx.CFrame  = ct.CFrame + Vector3.new(0, 0.05, 0)
	fx.Parent  = Workspace

	local s    = ct.Size
	local goal = Vector3.new(s.X * Config.Pulse.Scale, s.Y, s.Z * Config.Pulse.Scale)
	local tw   = TweenService:Create(
		fx,
		TweenInfo.new(Config.Pulse.Time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = goal, Transparency = 1 }
	)
	tw.Completed:Once(function() fx:Destroy() end)
	tw:Play()
end

TileStepped.OnClientEvent:Connect(function(model)
	pulse(model)
end)
