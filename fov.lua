local ffi = require "ffi"
local tiles = require "tiles"


ffi.cdef [[
	typedef struct {
		int idx, len;
		double angle[600];
		color light[600];

		color last_cell_color;
	} fovhead;
]]

local bufs = {ffi.new("fovhead"), ffi.new("fovhead")}

function fovhead_zoomto(dest, src, close_angle, inv_angle, cell_color, sum)
	local endangle = dest.angle[dest.idx - 1]
	
	if dest.idx > 1 then
		local lcc = dest.last_cell_color
		if	cell_color.r == dest.last_cell_color.r
			and cell_color.g == dest.last_cell_color.g
			and cell_color.b == dest.last_cell_color.b
		then
			-- we're rewinding the _destination_ tape but not the _source_ tape
			-- (and we're keeping the real 'firstangle'
			dest.idx = dest.idx - 1
		end
	end
	
	-- we run from firstangle to close_angle, copying whatever angles and
	-- colors we see in src as we run them, but filtering (i.e., multiplying)
	-- them by cell_color before writing them out

	sum.r, sum.g, sum.b = 0, 0, 0 

	if (cell_color.r + cell_color.g + cell_color.b) == 0 then
		-- zip past all the input and then just write a single chunky block
		local breakout = false
		while src.idx < src.len do
			local oldangle = endangle
			endangle = src.angle[src.idx]

			if endangle >= close_angle then
				endangle = close_angle
				breakout = true
			end

			local angle = endangle - oldangle
			local s = src.light[src.idx]
			sum.r, sum.g, sum.b =
				sum.r + angle * s.r,
				sum.g + angle * s.g,
				sum.b + angle * s.b

			if breakout then
				break
			end
			src.idx = src.idx + 1
		end

		dest.angle[dest.idx] = close_angle
		dest.light[dest.idx] = cell_color
		dest.idx = dest.idx + 1

		dest.last_cell_color = cell_color
	else
		local breakout = false
		while src.idx < src.len do
			local oldangle = endangle
			endangle = src.angle[src.idx]

			-- now check whether this source angle goes farther than we need right now
			if endangle > close_angle then
				endangle = close_angle
				breakout = true
			end

			local angle = endangle - oldangle
			local d, s = dest.light[dest.idx], src.light[src.idx]
			sum.r, sum.g, sum.b =
				sum.r + angle * s.r,
				sum.g + angle * s.g,
				sum.b + angle * s.b

			dest.angle[dest.idx] = endangle

			d.r, d.g, d.b = 
				s.r * cell_color.r,
				s.g * cell_color.g,
				s.b * cell_color.b

			dest.idx = dest.idx + 1

			if breakout then
				break
			else
				src.idx = src.idx + 1
			end
		end

		dest.last_cell_color = cell_color
	end

	sum.r, sum.g, sum.b, sum.a = sum.r * inv_angle, sum.g * inv_angle, sum.b * inv_angle, 1.0
	
	return sum
end

local clear = color(1, 1, 1, 1)
local opaque = color(0, 0, 0, 0)

local function fov(board, output, view_x, view_y, mask)
	local src, dest = bufs[1], bufs[2]
	local range = math.ceil(math.max(output.height, output.width) / 2)

	-- these three lines make it so you can see the cells next to you
	src.len = 2
	src.angle[1] = 1.1 
	src.light[1] = clear

	dest.angle[0] = 0
	src.angle[0] = 0

	-- output.recenter(view_x, view_y) -- this is now an external requirement
	output.fill(opaque)
	output.set(view_x, view_y, clear)

	if mask ~= nil then
		mask.recenter(view_x, view_y)
	else
		mask = nonmask
	end

	local board_info = board.summaries
	local out_cells, out_width = output.cells, output.width
	
	for z = 1, range - 1 do
		local x, y = view_x - z, view_y - z
		local idx = output.index(x, y)

		local sidelength = 2.0 * z
		local inv_cell_length = (4.0 * sidelength)
		local cell_length = 1 / (4.0 * sidelength)
		local cellnumber = .5
		
		src.idx, dest.idx = 1, 1

		for side = 0, 3 do
			local dx, dy, didx

			if side == 0 then dx, dy, didx = 1, 0, 1
			elseif side == 1 then dx, dy, didx = 0, 1, out_width
			elseif side == 2 then dx, dy, didx = -1, 0, -1
			elseif side == 3 then
				dx, dy, didx = 0, -1, -out_width
				sidelength = sidelength + 1.0 	
			end
				
			for t = 1, sidelength do
				local close = cellnumber * cell_length
				local index = board.index(x, y) -- branching in here is probably slow
				local m = mask.get(x, y)

				if true or index > 0 and m > 0.0 then 
					-- the commented test makes it faster, but causes weird artifacts
					local info = board_info[index]
					fovhead_zoomto(dest, src, close, inv_cell_length, info.transparency, out_cells[idx])
					out_cells[idx]:scale(m)
				else
					-- a hack to keep the skipping happy.  doesn't work, though.
					dest.angle[dest.idx - 1] = close
				end
				
				x, y, idx = x + dx, y + dy, idx + didx

				cellnumber = cellnumber + 1
			end
		end
		dest.len = dest.idx

		-- swap!
		src, dest = dest, src
	end
end

local nonmask = {
	get = function () return 1.0 end
}

local mask_cache = {
	circle = setmetatable({ }, {__mode == "v"})
}

local function circle_mask(radius)
	if mask_cache.circle[radius] ~= nil then
		return mask_cache.circle[radius]
	end

	local edge = 1 + radius * 2
	local output = tiles.layer("float", edge, edge)
	local r2 = (radius + 1) * (radius + 1)
	local falloff_r2 = (radius) * (radius)
	local c3p0 = 1 / (r2 - falloff_r2)

	output.fill(1.0)
	output.setdefault(0.0)
	output.recenter(0, 0)

	local lower_y = -(radius + .5)
	for y = -radius, 0 do
		local outer_x = math.sqrt(r2 - y * y)
		local inner_x = math.sqrt(falloff_r2 - y * y)
		for x = -radius, -math.floor(outer_x) do
			output.set(x, y, 0.0)
			output.set(-x, y, 0.0)
			output.set(x, -y, 0.0)
			output.set(-x, -y, 0.0)
		end
		for x = math.floor(-outer_x), -math.floor(inner_x) do
			local d2 = y * y + x * x
			local m = c3p0 * (r2 - d2)
			if (0 < m and m < 1) then
				output.set(x, y, m)
				output.set(-x, y, m)
				output.set(x, -y, m)
				output.set(-x, -y, m)
			end
		end
	end

	mask_cache.circle[radius] = output
	return output

	--circular_range = circular_range or 2 + 1.5 * range
	
	--local falloff_r2 = ((circular_range - 1) * (circular_range - 1))
	--local r2 = (circular_range * circular_range)
	
	-- anti-alias the edges! (it would be faster to do this in a separate pass)
	--if d2 > falloff_r2 then
		--out_cells[idx]:scale(c3p0 * (r2 - d2))
	--end 
end

return {
	scan = fov,
	mask = {
		circle = circle_mask
	}
}

