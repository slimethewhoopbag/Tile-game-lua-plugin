--!nonstrict
--[[ ScreenEffects — ReplicatedStorage > Shared > ScreenEffects (ModuleScript).

	Owns the local player's screen overlays. Required by TileVisualsClient.
	  ScreenEffects.init()          create the GUI (call once)
	  ScreenEffects.setVoid(mode)   "none" | "dark" | "light" (persistent tint)
	  ScreenEffects.flash(color)    quick damage/feedback flash
]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local ScreenEffects = {}
local gui, blind, flashFrame
local voidMode = "none"

function ScreenEffects.init()
	if gui then return end
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Instance.new("ScreenGui")
	gui.Name = "CurrentEffects"; gui.IgnoreGuiInset = true; gui.ResetOnSpawn = false; gui.Parent = pg

	blind = Instance.new("Frame")
	blind.Size = UDim2.fromScale(1,1); blind.BorderSizePixel = 0
	blind.BackgroundColor3 = Config.Void.Dark; blind.BackgroundTransparency = 1; blind.ZIndex = 10; blind.Parent = gui

	flashFrame = Instance.new("Frame")
	flashFrame.Size = UDim2.fromScale(1,1); flashFrame.BorderSizePixel = 0
	flashFrame.BackgroundColor3 = Color3.new(1,0,0); flashFrame.BackgroundTransparency = 1; flashFrame.ZIndex = 9; flashFrame.Parent = gui

	voidMode = "none"
end

function ScreenEffects.setVoid(mode)
	if not gui then ScreenEffects.init() end
	if mode == voidMode then return end
	voidMode = mode
	if mode == "none" then
		TweenService:Create(blind, TweenInfo.new(Config.Void.FadeTime), { BackgroundTransparency = 1 }):Play()
	else
		blind.BackgroundColor3 = (mode == "light") and Config.Void.Light or Config.Void.Dark
		TweenService:Create(blind, TweenInfo.new(Config.Void.FadeTime), { BackgroundTransparency = Config.Void.Tint }):Play()
	end
end

function ScreenEffects.flash(color)
	if not gui then ScreenEffects.init() end
	flashFrame.BackgroundColor3 = color or Color3.new(1,0,0)
	flashFrame.BackgroundTransparency = 0.35
	TweenService:Create(flashFrame, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
end

return ScreenEffects
