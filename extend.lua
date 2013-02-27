-- EXTEND RL
--[[ rl.compass = {
	W = {-1, 0},
	NW = {-1, -1},
	N = {0, -1},
	NE = {1, -1},
	E = {1, 0},
	SE = {1, 1},
	S = {0, 1},
	SW = {-1, 1}
} ]]


local ffi = require "ffi"

-- EXTEND OS
do
	local exit_list = {}
	local exit = os.exit
	local gcwatch = newproxy(true)

	local function cleanup()
		if exit_list ~= nil then
			for x = #exit_list, 1, -1 do
				local func = exit_list[x]
				func()
			end
			exit_list = nil
			gcwatch = nil
		end
	end

	getmetatable(gcwatch).__gc = cleanup

	function os.exit (...)
		cleanup()
		exit(...)
	end

	function os.atexit (fn)
		exit_list[1 + #exit_list] = fn
	end
end

-- EXTEND GLOBAL

_G.printtree = function (obj, key, indent)
	indent = indent or 0
	if type(obj) == "table" then
		print (string.rep(" ", indent) .. tostring(key) .. " = {")
		for k, v in pairs(obj) do
			printtree(v, k, indent + 2)
		end
		print (string.rep(" ", indent) .. "}" .. " (" .. tostring(obj) .. ")")
	else
		print (string.rep(" ", indent) .. tostring(key) .. " = " .. tostring(obj))
	end
end


--add color
ffi.cdef [[
	typedef struct {
		float r, g, b, a;
	} color;
]]

local color, vector

color = ffi.metatype("color", {
	__index = {
		clip = function(a)
			local r, g, b
			if a.r < 0 then r = 0 elseif a.r >= 1 then r = 255 else r = 255 * a.r end
			if a.g < 0 then g = 0 elseif a.g >= 1 then g = 255 else g = 255 * a.g end
			if a.b < 0 then b = 0 elseif a.b >= 1 then b = 255 else b = 255 * a.b end
			return r, g, b 
		end,
		stack = function(a, b)
			local aa = 1.0 - b.a
			a.r, a.g, a.b =
			aa * a.r + b.r, aa * a.g + b.g, aa * a.b + b.b
		end,
		add = function(a, b, s)
			a.r, a.g, a.b, a.a =
			a.r + s * b.r, a.g + s * b.g, a.b + s * b.b, a.a + s
		end,
		mul = function(a, b)
			a.r, a.g, a.b, a.a = a.r * b.r, a.g * b.g, a.b * b.b, a.a * b.b
		end,
		max = function(a, b)
			if a.r < b.r then a.r = b.r end
			if a.g < b.g then a.g = b.g end
			if a.b < b.b then a.b = b.b end
		end,
		scale = function(a, s)
			a.r, a.g, a.b = a.r * s, a.g * s, a.b * s
		end,
		add_mul = function(a, b, c, s)
			a.r, a.g, a.b =
				a.r + b.r * c.r * s,
				a.g + b.g * c.g * s,
				a.b + b.b * c.b * s
		end,
		set = function(a, b)
			a.r, a.g, a.b, a.a = b.r, b.g, b.b, b.a
		end,
		zero = function(a)
			a.r, a.g, a.b, a.a = 0, 0, 0, 0
		end,
		scale_alpha = function(a)
			local inv_a = 1 / a.a
			a.r, a.g, a.b, a.a = a.r * inv_a, a.g * inv_a, a.b * inv_a, 1.0
		end,
		iswhite = function(a)
			return a.r + a.g + a.b == 3.0
		end,
		isblack = function(a)
			return a.r + a.g + a.b == 0.0
		end
	},
	__mul = function (a, b) 
		if type(b) == "number" then
			return color(a.r * b, a.g * b, a.b * b, a.a)
		else
			return color(a.r * b.r, a.g * b.g, a.b * b.b, a.a * b.a)
		end
	end,
	__add = function(a, b)
		-- ignores alpha
		return color(a.r + b.r, a.g + b.g, a.b + b.b, 1)
	end
})

_G.color = color

-- EXTEND TABLE
table.clone = table.clone or function (table)
	local new = { }
	for k, v in pairs(table) do new[k] = v end
	return new
end

table.deepclone = function (table)
	local copies = { }
	local function innerclone (table)
		if copies[table] ~= nil then
			return copies[table]
		else
			local new = { }
			copies[table] = new

			for k, v in pairs(table) do
				if type(k) == "table" then k = innerclone(k) end
				if type(v) == "table" then v = innerclone(v) end

				new[k] = v
			end

			return new
		end
	end
	return innerclone(table)
end

io.serialize = function (file, value)
	local visited = { }
	if type(file) == "string" then
		file = io.open(file, "w")
	end
	file:write "return "
	local function inner(value, outertab)
		local out = ""
		local tab = outertab .. " "
		if value == nil then
			file:write "nil"
		elseif type(value) == "table" then
			local comma = false
			file:write (outertab, "{")
			for i = 1, #value do
				if comma then file:write (",", tab) end
				inner(value[i], tab)
				comma = true
			end
			for k, v in pairs(value) do
				if type(k) == "number" then
					if k < 1 or k > #value or k ~= math.floor(k) then
						if comma then file:write (",", tab) end
						file:write(tab, "[", tostring(k), "]=")
						inner(v, tab)
						comma = true
					end
				elseif type(k) == "string" then
					if comma then file:write "," end
					if string.match(k, "^[_%w]+$") then
						file:write(tab, k, "=")
						inner(v, tab)
					else
						file:write(tab, "[", string.format("%q", k), "]=")
					end
					comma = true
				elseif type(k) == "boolean" then
					if comma then file:write ", " end
					file:write(tab, "[", tostring(k), "]=")
					inner(v, tab)
					comma = true
				end
			end
			file:write (outertab, "}")
		elseif type(value) == "string" then
			file:write(string.format("%q", value))
		elseif type(value) == "number" then
			file:write(tostring(value))
		elseif type(value) == "boolean" then
			if value then
				file:write "true"
			else
				file:write "false"
			end
		end
	end
	inner(value, "\n")
end

-- EXTEND STRING SPLIT
string.split = string.split or function (S, J)
	assert(type(S) == "string", "split expects a string")

	local words = { }
	local start = 1

	if type(J) ~= "string" then J = "," end

	while start < #S + 1 do
		local last = (string.find(S, J, start, true) or (#S + 1)) - 1
		words[#words + 1] = S:sub(start, last)

		start = last + 1 + #J
	end

	return words
end

math.sgn = function(n)
	if n > 0 then
		return 1, n
	elseif n < 0 then
		return -1, -n
	else
		return 0, 0
	end
end

