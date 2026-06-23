--!nonstrict
--[[ TileDatabase — ReplicatedStorage > Shared > TileDatabase (ModuleScript). REPLACES old one.

	Readability pass: muted colours, mostly SmoothPlastic. Soft "weak neon" only for
	signal tiles (Goal, Beacon, Warp, Lava); Glass only for Ice. New: Lava.

	Flags:
	  Hazard         damages by default
	  Neutralizable  a hazard an adjacent neutralizer can make safe (Shock)
	  IsNeutralizer  deactivates adjacent Neutralizable hazards (Inverter)
]]

local TileDatabase = {}

TileDatabase.Types = {
	Stone="Stone", Spawn="Spawn", Goal="Goal", Shock="Shock", Spring="Spring",
	Ice="Ice", Void="Void", Beacon="Beacon", Inverter="Inverter", Crumble="Crumble",
	Phantom="Phantom", Warp="Warp", Push="Push", Lava="Lava",
}

local SP   = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local GLASS= Enum.Material.Glass

TileDatabase.Definitions = {
	Stone    = { Color=Color3.fromRGB(120,124,130), Material=SP,   Hazard=false, Neutralizable=false, IsNeutralizer=false },
	Spawn    = { Color=Color3.fromRGB(216,219,224), Material=SP,   Hazard=false, Neutralizable=false, IsNeutralizer=false },
	Goal     = { Color=Color3.fromRGB(206,170,92),  Material=NEON, Hazard=false, Neutralizable=false, IsNeutralizer=false },
	Shock    = { Color=Color3.fromRGB(208,196,118), Material=SP,   Hazard=true,  Neutralizable=true,  IsNeutralizer=false },
	Spring   = { Color=Color3.fromRGB(126,178,134), Material=SP,   Hazard=false, Neutralizable=false, IsNeutralizer=false },
	Ice      = { Color=Color3.fromRGB(165,196,214), Material=GLASS,Hazard=false, Neutralizable=false, IsNeutralizer=false },
	Void     = { Color=Color3.fromRGB(44,46,54),    Material=SP,   Hazard=false, Neutralizable=false, IsNeutralizer=false },
	Beacon   = { Color=Color3.fromRGB(196,116,116), Material=NEON, Hazard=false, Neutralizable=false, IsNeutralizer=false },
	Inverter = { Color=Color3.fromRGB(158,130,184), Material=SP,   Hazard=false, Neutralizable=false, IsNeutralizer=true },
	Crumble  = { Color=Color3.fromRGB(188,142,98),  Material=SP,   Hazard=false, Neutralizable=false, IsNeutralizer=false },
	Phantom  = { Color=Color3.fromRGB(176,173,186), Material=SP,   Hazard=false, Neutralizable=false, IsNeutralizer=false },
	Warp     = { Color=Color3.fromRGB(118,182,180), Material=NEON, Hazard=false, Neutralizable=false, IsNeutralizer=false },
	Push     = { Color=Color3.fromRGB(198,150,172), Material=SP,   Hazard=false, Neutralizable=false, IsNeutralizer=false },
	Lava     = { Color=Color3.fromRGB(206,98,74),   Material=NEON, Hazard=true,  Neutralizable=false, IsNeutralizer=false },
}

function TileDatabase.get(name)
	return TileDatabase.Definitions[name] or TileDatabase.Definitions.Stone
end
function TileDatabase.isHazard(name) return TileDatabase.get(name).Hazard == true end

return TileDatabase
