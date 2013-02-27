local ffi = require "ffi"

local function new_layer(ctype, width, height) 
	local self

	local x1, y1, default = 1, 1, 0
	local cells = ffi.new(ctype .. "[?]", 1 + width * height)

	local function index(x, y)
		x, y = x - x1, y - y1
		if x < 0 or y < 0 or x >= width or y >= height then
			return 0
		else
			return 1 + x + y * width
		end
	end

	local function get(x, y)
		return cells[index(x, y)]
	end

	local function set(x, y, v)
		x, y = x - x1, y - y1
		if x < 0 or y < 0 or x >= width or y >= height then
			return
		end

		cells[1 + x + y * width] = v
		return self
	end

	local function moveto(x, y)
		x1, y1 = x, y
		self.x1, self.y1, self.x2, self.y2 = x1, y1, x1 + width - 1, y1 + height - 1
		return self
	end

	local function recenter(x, y)
		x1, y1 = x - math.floor(width / 2), y - math.floor(height / 2)
		self.x1, self.y1, self.x2, self.y2 = x1, y1, x1 + width - 1, y1 + height - 1
		return self
	end

	local function fill(v)
		for i = 1, width * height do
			cells[i] = v
		end
		return self
	end
	
	local function setdefault(v)
		cells[0] = v
		return self
	end

	local function each(f)
		local i = 1
		for y = y1, y1 + height - 1 do
			for x = x1, x1 + width - 1 do
				f(cells[i], x, y)
				i = i + 1
			end
		end
		return self
	end
	
	self = {
		moveto = moveto,
		recenter = recenter,

		each = each,
		cells = cells,
		index = index,
		get = get,
		set = set,
		setdefault = setdefault,
		fill = fill,

		ctype = ctype,

		width = width,
		height = height,

		-- read only:
		x1 = x1, y1 = y1,
		x2 = x1 + width - 1, y2 = y1 + height - 1
	}

	return self
end

return {
	new = new_layer
}
