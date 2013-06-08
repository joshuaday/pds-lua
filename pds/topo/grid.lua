-- still some room for micro-optimization here

local Grid = { }
local grid = { }
local grid_mt = {__index = grid}

local Overlay = require "pds/overlay"
local ffi = require "ffi"

local POINT_CTYPE = "struct pds_topo_grid_point"
ffi.cdef (POINT_CTYPE .. [[ {int x, y;}; ]])

local new_point = ffi.typeof(POINT_CTYPE)

function grid:index(point)
	if point.x < 1 or point.y < 1 or point.x > self.width or point.y > self.height then
		return 0
	else
		return point.x + (point.y - 1) * self.width
	end
end

function grid:index_unpack(point, idx)
	if idx == 0 then
		return false
	else
		point.x, point.y = 1 + (idx - 1) % self.width, 1 + math.floor((idx - 1) / self.width)
		return true
	end
end

-- for neighbors, state must be an integer, and will always be 0 on the first call;
-- after that, it will be whatever you returned last, but it must be numerical.


-- the returned cost must be _valid_, that is, must satisfy two requirements:
--  1) it must be at least equal to prior for all possible priors
--  2) for prior costs A1 and A2, A1 < A2, posterior costs P1 and P2 must satisfy P1 <= P2
--     imagine it like this: suppose a neighbor contains a door that will open in five turns.
--     In this case, for A1 < A2 < 5, P1 = P2 = 5.
--  3) if this cell should not be entered, because it will become dangerous again, then all
--     neighbors should indicate, as a posterior cost to enter it, the time when it will be
--     safe again to enter; custom monster logic is necessary to cause a monster to leave the
--     cell if it is already in it, and does not fall under the purview of the pds.

function grid:neighbor(idx, costmap, prior, state)
	while state < #self.connectivity do 
		state = state + 1
		local neighbor = idx + self.connectivity[state]

		
		-- checks for diagonals go here, too
		local cost = costmap.cells[neighbor]
		if cost >= 0 then
			return neighbor, cost + prior, state
		end
	end
end

function grid:lattice( )
	local x, y, idx = 1, 1, 0
	local function iterator()
		if y > self.height then
			return nil
		end

		local x1, y1 = x, y

		idx = idx + 1
		if x == self.width then
			x = 1
			y = y + 1
		else
			x = x + 1
		end
		
		return x1, y1, idx
	end

	return iterator
end

function Grid.new(width, height, connectivity)
	local self = setmetatable ({
		width = width,
		height = height,
		length = width * height,
		point_ctype = POINT_CTYPE,

		cursor = new_point,
		overlay = Overlay.new,

		overlays = setmetatable({}, {__mode = "k"})
	}, grid_mt)

	if connectivity == 4 then
		rawset(connectivity, {-width, 1, width, -1})
	elseif connectivity == 6 then
		rawset(connectivity, {-width, -width + 1, 1, width, width - 1, -1})
	else 
		rawset(self, "connectivity", {-width - 1, -width, -width + 1, 1, 1 + width, width, width - 1, -1})
		-- diagonal connectivity rules can be optional though
		rawset(self, "diagonal_y", {-width, 0, -width, 0, width, 0, width, 0})
		rawset(self, "diagonal_x", {-1, 0, 1, 0, 1, 0, -1, 0})
	end

	return self
end

return Grid

