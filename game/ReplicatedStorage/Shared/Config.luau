--!nonstrict
--[[ Config — ReplicatedStorage > Shared > Config (ModuleScript). REPLACES old one.

	Tile spacing is now taken from ReplicatedStorage.Tiles.BasicTile.PrimaryPart.Size
	(+ Gap). TileSize below is only a fallback if that model is missing.
]]

local Config = {}

Config.Grid = {
	Origin = Vector3.new(0, 100, 0),   -- world centre of tile (1,1); players stand at Origin.Y
	Width = 18, Length = 40,
	Gap = 0.2,                         -- visual gap between tile models
	TileSize = 8,                      -- fallback only; real pitch comes from PrimaryPart
}

Config.Round = {
	Lives = 3,
	ScanRate = 0.03,
}

Config.Fog = {
	Enabled    = true,
	Radius     = 2,      -- box radius: 2 => 5x5 reveal, 3 => 7x7, etc.
	FrontRows  = 2,      -- rows nearest the spawn that start revealed
	RingDelay  = 0.06,   -- delay between each expanding ring (center -> 3x3 -> 5x5 ...)
	FadeTime   = 0.25,   -- how long each fog puff takes to clear
	PulseScale = 1.35,   -- how far a fog puff grows as it clears
}

-- Spawn: players start on a gray platform behind the grid, not on a tile.
Config.Spawn = {
	PlatformWidthTiles = 20,                       -- platform width, in tiles
	PlatformDepth      = 28,                        -- platform depth in studs (Z)
	GapBehind          = 0,                          -- studs between platform and the grid's front edge
	Color              = Color3.fromRGB(105, 105, 110),
}

Config.Debug = {
	ShowSafePath = true,                       -- master switch for the safe-path debug paint
	PaintMode    = "Touch",                    -- ONE-LINER: "All" = whole path at build, "Touch" = light per step
	PathColor = Color3.fromRGB(70, 210, 95),
}

-- Pulse: client clones the ColorTile, grows it on the XZ plane and fades it out.
Config.Pulse = { Time = 0.35, Scale = 1.4 }

Config.Spring = { Default = 7.2, High = 20, Low = 2 }
Config.Ice    = { Friction = 0.02, GrippyFriction = 2.0, Weight = 100 }
Config.Void   = { Tint = 0.05, FadeTime = 0.2, Dark = Color3.new(0,0,0), Light = Color3.new(1,1,1) }
Config.Shock   = { AoeRadius = 10 }
Config.Crumble = { Delay = 1.0, DropTime = 8 }


Config.Push = {
	Cooldown     = 0.6,
	SlidePerTile = 0.09,
	SlideTime    = 0.12,   -- fallback
	MinTime      = 0.12,
	MaxTime      = 0.5,
	LandBuffer   = 0.15,   -- extra invulnerable time after the slide before the target tile fires
}

Config.Warp = { Lock = 0.6 }

return Config
