local ffi = require "ffi"
local mobs = require "mobs"
local tiles = require "tiles"
local random = require "random"

local stone = tiles.types.stone
local grass = tiles.types.grass
local water = tiles.types.deepwater
local shallowwater = tiles.types.shallowwater
local wall = tiles.types.wall
local door = tiles.types.door
local tree = tiles.types.tree
local brush = tiles.types.brush
local glass = tiles.types.glass
local glower = tiles.types.glower

ffi.cdef [[
	typedef struct {int x, y;} region_point;
]]

local point = ffi.typeof("region_point")

-- ditching regions for the moment -- hoping they emerge naturally
local function region(width, height)
	local self
	local l = tiles.layer("int", width, height)

	l.fill(1) -- member
	l.moveto(0, 0)
	l.setdefault(0) -- non-member

	local function crop(n)
		local x1, y1, x2, y2 = l.x2, l.y2, l.x1, l.y1
		l.each(function(i, x, y)
			if i == n then
				if x < x1 then x1 = x end
				if y < y1 then y1 = y end
				if x > x2 then x2 = x end
				if y > y2 then y2 = y end
			end
		end)
		
		if x1 > x2 then
			x2, y2 = x1, y1
		end

		local new_l = tiles.layer("int", 1 + x2 - x1, 1 + y2 - y1)
		new_l.each(function(i, x, y)
			new_l.set(x, y, l.get(x, y))
		end)
		new_l.setdefault(l.get(l.x1 - 1, l.y1 - 1))
		
		l = new_l
	end
	
	self = {
		crop = crop
	}
	return self
end


local function spill(workspace, x, y)
	local front_x, front_y = { }, { }

	local function touch(x, y)
		if workspace.get(x, y) == 0 then
			front_x[1 + #front_x] = x
			front_y[1 + #front_y] = y
			workspace.set(x, y, 1)
		end
	end
	
	local function accept()
		touch(x - 1, y)
		touch(x + 1, y)
		touch(x, y - 1)
		touch(x, y + 1)
	end

	local function iterator()
		if #front_x > 0 then
			local i = random.index(front_x)
			x, y = front_x[i], front_y[i]

			front_x[i] = front_x[#front_x]
			front_y[i] = front_y[#front_y]
			front_x[#front_x] = nil
			front_y[#front_y] = nil

			return accept, x, y
		else
			return nil
		end
	end

	workspace.fill(0)
	workspace.setdefault(1)

	touch(x, y)
	return iterator
end


local function compute_normals(level, height)
	local CELL_SIZE = 1
	level.each(function(info, x, y)
		local hn, hs, hw, he =
			height.get(x, y - 1), height.get(x, y + 1), 
			height.get(x - 1, y), height.get(x + 1, y)

		local ddx = -.5 * (he - hw)
		local ddy = -.5 * (hs - hn)

		local normalsize = 1.0 / math.sqrt(ddx * ddx + ddy * ddy + CELL_SIZE * CELL_SIZE)

		info.normal[0], info.normal[1], info.normal[2] = 
			ddx * normalsize,
			ddy * normalsize,
			CELL_SIZE * normalsize
	end)
end

local function entry(level)
	level.lock()
	local workspace = tiles.layer("int", level.width, level.height)
	local heightmap = tiles.layer("float", level.width, level.height)

	heightmap.each(function(cell, x, y)
		heightmap.set(x, y, random.unit)
	end)
	heightmap.setdefault(.5)
	compute_normals(level, heightmap)

	level.each(function(info, x, y)
		level.add(x, y, stone)

		--local normal = inplace.normalize(vector(random.unit, random.unit, 2))
		--info.normal = normal
		--info.normal = normal
		--info.normal[0], info.normal[1], info.normal[2] = normal[1], normal[2], normal[3]
	end)
	
	local function spill_some(template, template_b)
		local count = 40 + random.int(30)
		local cx, cy = random.range(0, level.width-1), random.range(0, level.height-1)

		for accept, x, y in spill(workspace, cx, cy) do
			if count > 0 then
				level.add(x, y, template)
				count = count - 1
				accept()
			else
				if template_b ~= nil then
					level.add(x, y, template_b)
				else
					if workspace.get(x - 1, y) + workspace.get(x + 1, y)
						+ workspace.get(x, y - 1) + workspace.get(x, y + 1) >= 3 then
						level.add(x, y, template)
					end
				end
			end
		end
	end

	for i = 1, 7 do
		--spill_some(grass)
		spill_some(water, shallowwater)
	end

	do
		local x1, y1 = 13, 17
		local w, h = 9, 7
		for x = 0, w-1 do
			level.add(x + x1, y1, wall)
			if x ~= 3 then level.add(x + x1, y1 + h - 1, wall)
			else level.add(x + x1, y1 + h - 1, door) end
		end
		for y = 0, h-1 do
			level.add(x1, y + y1, wall)
			level.add(x1 + w - 1, y + y1, wall)
		end
	end
			

	level.add(level.width - 5, level.height / 2 - 1, tiles.types.stair_down)
	level.add(level.width - 5, level.height / 2, tiles.types.stair_down)
	level.add(level.width - 5, level.height / 2 + 1, tiles.types.stair_down)
	level.add(level.width - 6, level.height / 2, mobs.types.kali)
	level.unlock()
end

local function terrible(level)
	level.lock()

	local heightmap = tiles.layer("float", level.width, level.height)
	heightmap.each(function(cell, x, y)
		heightmap.set(x, y, random.unit)
	end)
	heightmap.setdefault(.5)
	compute_normals(level, heightmap)

	level.each(function(info, x, y)
		level.add(x, y, grass)
		if level.on_edge(x, y)
		then level.add(x, y, wall) 
		elseif random.unit > .97 then
			local cobra = level.add(x, y, mobs.types.cobra)
			
			--local glow = level.add(x, y, glower)
			--glow.light = color (2 * random.unit, 2 * random.unit, 1 * random.unit, random.unit + .4)
		end
		--[[elseif random.unit > .95 then
			level.add(x, y, tree)
		elseif random.unit > .95 then
			level.add(x, y, glass)
		end]]
		
		--[[if x == 15 then
			local a = 1
			local roygbiv = {{1, 0, 0, a}, {1, .5, 0, a}, {1, 1, 0, a}, {0, 1, 0, a}, {0, .5, 1, a}, {0, 0, 1, a}, {1, 0, 1, a}}
			--local roygbiv = {{1, .5, .5, a}, {.5, 1, .5, a}, {.5, .5, 1, a}}
			local color = color(roygbiv[1 + y % #roygbiv])
			local window = level.add(x, y, glass)
			window.bg = color
			window.transparency = color
		end]]
	end).summarize()
	
	if level.up ~= nil then
		local injections = level.up.inject_below
		for i = 1, #injections do
			local x, y = injections[i].x, injections[i].y
			if x ~= nil then -- still on the level
				level.add(x, y, tiles.types[injections[i].inject_below])
			end
		end
	end

	level.unlock()
end


return {
	entry = entry,
	terrible = terrible
}

