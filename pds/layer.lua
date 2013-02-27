local ffi = require "ffi"

local layer = { }

local layer_mt = { __index = layer }

function layer:index(x, y)
	x, y = x - self.x1, y - self.y1
	if x < 0 or y < 0 or x >= self.width or y >= self.height then
		return 0
	else
		return 1 + x + y * self.width
	end
end

function layer:get(x, y)
	return self.cells[self:index(x, y)]
end

function layer:set(x, y, v)
	x, y = x - self.x1, y - self.y1
	if x < 0 or y < 0 or x >= self.width or y >= self.height then
		return
	end

	self.cells[1 + x + y * self.width] = v
	return self
end

function layer:moveto(x, y)
	x1, y1 = x, y
	self.x1, self.y1, self.x2, self.y2 = x1, y1, x1 + width - 1, y1 + height - 1
	return self
end

function layer:recenter(x, y)
	x1, y1 = x - math.floor(self.width / 2), y - math.floor(self.height / 2)
	self.x1, self.y1, self.x2, self.y2 = x1, y1, x1 + self.width - 1, y1 + self.height - 1
	return self
end

function layer:fill(v)
	for i = 1, self.width * self.height do
		cells[i] = v
	end
	return self
end

function layer:setdefault(v)
	self.cells[0] = v
	return self
end

function layer:each(f)
	local i = 1
	for y = self.y1, self.y2 do
		for x = self.x1, self.x2 do
			f(self.cells[i], x, y)
			i = i + 1
		end
	end
	return self
end


local function new_layer(ctype, width, height) 
	return setmetatable({
		x1 = 1,
		y1 = 1,
		x2 = x1 + width - 1,
		y2 = y1 + height - 1,
		width = width,
		height = height,

		cells = ffi.new(ctype .. "[?]", 1 + width * height)

		ctype = ctype
	}, layer_mt)
end

return {
	new = new_layer
}
