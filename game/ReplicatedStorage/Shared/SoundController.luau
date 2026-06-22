--!nonstrict
--[[ SoundController — ReplicatedStorage > Shared > SoundController (ModuleScript).

	Plays the combo sounds. Create ReplicatedStorage > Sounds > Combo, and put six
	Sound objects inside named "1" .. "6".

	SoundController.playCombo(index)  -- index 1..6
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")

local SoundController = {}
local warned = {}

local function getCombo(index)
	local sounds = ReplicatedStorage:FindFirstChild("Sounds")
	local combo  = sounds and sounds:FindFirstChild("Combo")
	return combo and combo:FindFirstChild(tostring(index))
end

function SoundController.playCombo(index)
	local template = getCombo(index)
	if not template or not template:IsA("Sound") then
		if not warned[index] then
			warn(("[CURRENT] Missing Sound at ReplicatedStorage.Sounds.Combo.%s"):format(tostring(index)))
			warned[index] = true
		end
		return
	end
	local clone = template:Clone()
	clone.Parent = SoundService          -- 2D (global to this client)
	clone:Play()
	clone.Ended:Once(function() clone:Destroy() end)
	task.delay(8, function() if clone and clone.Parent then clone:Destroy() end end)
end

return SoundController
