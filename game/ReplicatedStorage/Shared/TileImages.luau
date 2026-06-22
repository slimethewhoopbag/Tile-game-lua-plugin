--!nonstrict
--[[
	TileImages
	----------
	PLACE IN: ReplicatedStorage > Shared > TileImages   (ModuleScript)

	A database of images you can stamp onto tile faces (your "cipher").
	Paste asset ids as strings like "rbxassetid://123456789".

	HOW IT'S USED
	  * TilePlacer puts a Decal of Symbols[tileType] on a tile's top face
	    (if you've set an id for that type).
	  * Push tiles are special: instead of a single symbol they show
	    PushArrow repeated 1-3 times, rotated to the push direction.

	Leave an entry as "" to draw nothing for that tile (no broken image).
]]

local TileImages = {}

-- One symbol per tile type (fill these in as you make art). "" = none.
TileImages.Symbols = {
	Stone    = "",
	Spawn    = "rbxassetid://88530768462131",
	Goal     = "rbxassetid://106654820162434",
	Shock    = "rbxassetid://111923856200180",
	Spring   = "rbxassetid://111457370734023",
	Ice      = "",
	Void     = "rbxassetid://80319522205327",
	Beacon   = "rbxassetid://12115854683",
	Inverter = "rbxassetid://96498567035505",
	Crumble  = "",
	Phantom  = "rbxassetid://111954213123297",
	Warp     = "",
	-- Push uses PushArrow below, not this table.
}

-- The arrow stamped on Push tiles. Make it point "up" in the image;
-- TilePlacer rotates it to face the real push direction.
TileImages.PushArrow = "rbxassetid://17071686018"  -- e.g. "rbxassetid://000000000"

function TileImages.get(tileType)
	return TileImages.Symbols[tileType] or ""
end

return TileImages
