local ffi = require "ffi"
local pds = require "pds/pds"

local Overlay = { }
local overlay = { }
local overlay_mt = {
	__index = overlay
}

function overlay:fill(value)
	for i = 1, self.topology.length do
		self.cells[i] = value
	end
	return self
end

function overlay:zero()
	local oob = self.cells[0]
	ffi.fill(self.cells, ffi.sizeof(self.cells), 0)
	self.cells[0] = oob
	return self
end

function overlay:add(other, scale)
	assert(other.topology == self.topology)

	scale = scale or 1
	
	for i = 1, self.topology.length do
		self.cells[i] = self.cells[i] + scale * other.cells[i]
	end

	return self
end

function overlay:mul(other)
	assert(other.topology == self.topology)
	
	for i = 1, self.topology.length do
		self.cells[i] = self.cells[i] * other.cells[i]
	end

	return self
end

function overlay:map(other, fn)
	assert(other.topology == self.topology)
	
	for i = 1, self.topology.length do
		self.cells[i] = fn(self.cells[i], other.cells[i])
	end

	return self
end

function overlay:clone()
	local c = self.topology:overlay(self.ctype)

	ffi.copy(c.cells, self.cells, ffi.sizeof(self.cells))

	return c
end

function overlay:copyfrom(other)
	assert(other.topology == self.topology)
	
	ffi.copy(self.cells, other.cells, ffi.sizeof(other.cells))

	return self
end

function overlay:each(fn)
	for i = 1, self.topology.length do
		fn(self.cells[i], i)
	end

	return self
end

function overlay:get(point)
	return self.cells[self.topology:index(point)]
end

function overlay:rolldown(cells, point)
	local idx = self.topology:index(point)
	local go = pds.bestneighbor(self, cells, idx)
	self.topology:index_unpack(point, go)
end

function overlay:set(point, value)
	local idx = self.topology:index(point)
	if idx > 0 then
		self.cells[idx] = value
	end

	return self
end

function default(value)
	self.cells[0] = value
end

-- others to think about:
-- unm     -layer
-- sub     a-b
-- div     a/b   (path with b as costmap?)
-- mod     a%b
-- pow     a^b
-- concat  a..b
-- len    #a
-- eq    a==b
-- lt    a<b
-- le    a<=b
-- call  a()

function overlay_mt.__add(a, b)
	if getmetatable(a) ~= overlay_mt then
		a, b = b, a
	end

	local c = a.topology:overlay(a.ctype)
	if getmetatable(b) == overlay_mt then
		if a.topology ~= b.topology then
			error ("Cannot add overlays of unlike topology", 2)
		end
		for i = 1, a.topology.length do
			c.cells[i] = a.cells[i] + b.cells[i]
		end
	elseif type(b) == "number" then
		for i = 1, a.topology.length do
			c.cells[i] = a.cells[i] + b
		end
	else
		error ("Cannot add non-numeric type " .. type(b) .. " to an overlay", 2)
	end

	return c
end

function overlay_mt.__mul(a, b)
	if getmetatable(a) ~= overlay_mt then
		a, b = b, a
	end

	local c = a.topology:overlay(a.ctype)
	if getmetatable(b) == overlay_mt then
		if a.topology ~= b.topology then
			error ("Cannot multiply overlays of unlike topology", 2)
		end
		for i = 1, a.topology.length do
			c.cells[i] = a.cells[i] * b.cells[i]
		end
	elseif type(b) == "number" then
		for i = 1, a.topology.length do
			c.cells[i] = a.cells[i] * b
		end
	else
		error ("Cannot multiply non-numeric type " .. type(b) .. " by an overlay", 2)
	end

	return c
end

function overlay_mt.__div(a, b)
	-- todo : improve
	local c = a:clone()
	
	pds.dijkstra(b, c, a)

	return c
end


function Overlay.new(topology, ctype)
	-- the argument order on Overlay.new allows us to expose it as a method on a particular topology,
	-- which called as (say) grid:overlay "int" will call Overlay.new(grid, "int")

	if type(ctype) ~= "string" then
		if type(topology) == "string" then
			error ("Overlay.new(topology, ctype) -- perhaps you used . instead of :", 2)
		else
			error ("Overlay.new(topology, ctype), had (" .. type(topology) .. ", " .. type(ctype) .. ")" , 2)
		end
	end

	local self = setmetatable(
		{
			cells = ffi.new(ctype .. "[?]", 1 + topology.length),
			ctype = ctype,
			topology = topology
		}, overlay_mt
	)

	topology.overlays[self] = true

	return self
end

return Overlay

