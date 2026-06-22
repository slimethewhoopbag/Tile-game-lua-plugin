--!nonstrict
--[[ TileRules — ReplicatedStorage > Shared > TileRules (ModuleScript). NEW FILE.

	One place that decides "is this tile safe?" and "what does a Beacon reach?".
	PathGenerator (generation), GameManager (gameplay) and TilePlacer (visuals) all
	call into here, so they can never disagree about which tiles are neutralised or
	beacon-affected. That disagreement was the source of the inconsistent inversion
	and the "beacon effect with no beacon nearby" reports.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TileDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TileDatabase"))

local TileRules = {}

TileRules.Directions = {
	Up    = { dx = 0,  dz = 1 },
	Down  = { dx = 0,  dz = -1 },
	Left  = { dx = -1, dz = 0 },
	Right = { dx = 1,  dz = 0 },
}

-- HARD bound: a Beacon may only ever influence this many tiles along its PointDir.
TileRules.BeaconRange = 3

local NEIGHBOURS = { {1,0}, {-1,0}, {0,1}, {0,-1} }

-- A Phantom behaves as whatever it is hiding. Everything else is itself.
function TileRules.effectiveTile(cell)
	if cell.tile == "Phantom" then
		return cell.attr.Underlying or "Stone"
	end
	return cell.tile
end

function TileRules.hasAdjacentNeutralizer(grid, x, z)
	for _, off in ipairs(NEIGHBOURS) do
		local col = grid[x + off[1]]
		local n = col and col[z + off[2]]
		if n and TileDatabase.get(n.tile).IsNeutralizer then
			return true
		end
	end
	return false
end

-- "Grounded" = protected from electric AoE. True when the cell is switched off or it
-- sits next to a neutraliser (an Inverter grounds you).
function TileRules.isGrounded(grid, x, z)
	local col = grid[x]
	local cell = col and col[z]
	if not cell then return false end
	if cell.attr.Deactivated then return true end
	return TileRules.hasAdjacentNeutralizer(grid, x, z)
end

-- Is it safe to stand on this cell right now? Resolves Phantom disguises, so a Phantom
-- hiding electric next to an Inverter is treated exactly like a real electric tile next
-- to an Inverter: SAFE. This is what makes inversion behave consistently.
function TileRules.isCellSafe(grid, x, z)
	local col = grid[x]
	local cell = col and col[z]
	if not cell then return false end

	local def = TileDatabase.get(TileRules.effectiveTile(cell))
	if not def.Hazard then return true end             -- not a hazard at all
	if cell.attr.Deactivated then return true end      -- switched off (path / beacon)
	if def.Neutralizable and TileRules.hasAdjacentNeutralizer(grid, x, z) then
		return true                                    -- Inverter next door grounds it
	end
	return false
end

-- The cells a Beacon at (x,z) actually reaches: up to BeaconRange along PointDir, and
-- only cells that exist in the grid. It can NEVER reach further than BeaconRange.
function TileRules.beaconTargets(grid, x, z)
	local out = {}
	local col = grid[x]
	local cell = col and col[z]
	if not (cell and cell.tile == "Beacon" and cell.attr.PointDir) then
		return out
	end
	local d = TileRules.Directions[cell.attr.PointDir]
	if not d then return out end
	for s = 1, TileRules.BeaconRange do
		local nx, nz = x + d.dx * s, z + d.dz * s
		local ncol = grid[nx]
		if ncol and ncol[nz] then
			table.insert(out, { x = nx, z = nz })
		end
	end
	return out
end

return TileRules
