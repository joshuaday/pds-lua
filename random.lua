math.randomseed(os.time())

local function unit()
	return math.random()
end

local function int(max)
	return math.random(max) - 1
end

local function range(min, max)
	return math.random(min, max)
end

local function index(array)
	return math.random(#array)
end

local function __index(self, key)
	if key == "unit" then
		return unit()
	end
end

return setmetatable ({
	int = int,
	index = index,
	range = range
}, {
	__index = __index
})

