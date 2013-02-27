local ffi = require "ffi"

ffi.cdef [[
	typedef struct CIE {
		float X, Y, Z;
		float x, y, z;
	} CIE;

	typedef struct Lab {
		float L, a, b;
	} Lab;
]]

--palette pasted in from libtcod.lua
local palette = {
	{0,0,0},
	{128,0,0},
	{0,128,0},
	{140,128,40},
	{0,0,128},
	{128,0,128},
	{0,128,136},
	{128,128,128},
	
	{96,96,96},
	{255,0,0},
	{0,255,0},
	{255,240,60},
	{0,0,255},
	{255,0,255},
	{0,240,255},
	{255,255,255}
}

local fg_bias = ffi.new("double[?]", 16, {
	-500, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0
})
local bg_bias = ffi.new("double[?]", 8, {
	-1000, -500, -500, 1600, -500, 0, 600, 2300
})

local oversaturate


local ciePalette, labPalette, adamsPalette = 
	ffi.new("CIE[?]", 16),
	ffi.new("Lab[?]", 16),
	ffi.new("CIE[?]", 16)

local function toCIE(c)
	local a = 0.055
	
	-- http://en.wikipedia.org/wiki/SRGB_color_space#The_reverse_transformation

	local r, g, b = 
		c.r <= 0.04045 and c.r / 12.92 or math.pow((c.r + a) / (1 + a), 2.4),
		c.g <= 0.04045 and c.g / 12.92 or math.pow((c.g + a) / (1 + a), 2.4),
		c.b <= 0.04045 and c.b / 12.92 or math.pow((c.b + a) / (1 + a), 2.4)
	
	local cie = ffi.new("CIE")
	cie.X = 0.4124 * r + 0.3576 * g + 0.1805 * b
	cie.Y = 0.2126 * r + 0.7152 * g + 0.0722 * b
	cie.Z = 0.0193 * r + 0.1192 * g + 0.9505 * b
	
	local sum = cie.X + cie.Y + cie.Z
	if sum == 0.0 then sum = 1.0 end
	cie.x = cie.X / sum
	cie.y = cie.Y / sum
	cie.z = 1.0 - cie.x - cie.y
	
	return cie
end

local Labf_cutoff = ((6.0/29.0) * (6.0/29.0) * (6.0/29.0))
local Labf_factor = (1/3) * (29/6) * (29/6)
local Labf_sum = (4/29)
local function Labf(t)
	if t > Labf_cutoff then
		return math.pow(t, 1/3)
	else
		return Labf_factor * t + Labf_sum
	end
end

local white

local function toLab(cie)
	local n = ffi.new("CIE")
	n.X, n.Y, n.Z = Labf(cie.X / white.Y), Labf(cie.Y / white.Y), Labf(cie.Z / white.Z)

	local l = ffi.new("Lab")
	l.L = 116.0 * n.Y - 16
	l.a = 500.0 * (n.X - n.Y)
	l.b = 200.0 * (n.Y - n.Z)

	return l
end


local function munsellSloanGodlove(t) 
	return math.sqrt(1.4742 * t - 0.004743 * t * t);
end


local function adams(v)
	local c = ffi.new("CIE")

	c.Y = munsellSloanGodlove(v.Y)
	c.X = munsellSloanGodlove((white.Y / white.X) * v.X) - c.Y
	c.Z = munsellSloanGodlove((white.Z / white.X) * v.Z) - c.Y

	return c
end

local function SQUARE(x)
	return x * x
end

local function CIE76(L1, L2)
	-- http://en.wikipedia.org/wiki/Color_difference#CIE76
	local lbias = 1.0
	return math.sqrt(lbias * SQUARE(L2.L - L1.L) + SQUARE(L2.a - L1.a) + SQUARE(L2.b - L1.b))
end

local function CIExyY(L1, L2)
	-- this does a good job of estimating the difference between two colors, ignoring brightness
	
	return math.sqrt(SQUARE(L2.x - L1.x) + SQUARE(L2.y - L1.y))
end

local function adamsDistance(v1, v2)
	-- not really the right metric, this
	return sqrt(SQUARE(v2.X - v1.X) + SQUARE(v2.Y - v1.Y) + SQUARE(v2.Z - v1.Z))
end



local function initialize()
	local sRGB_white = color (1, 1, 1)
	white = toCIE(sRGB_white)

	for i = 0, 15 do
		palette[i] = color(palette[i + 1])

		ciePalette[i] = toCIE(palette[i])
		labPalette[i] = toLab(ciePalette[i])
		adamsPalette[i] = adams(ciePalette[i])
	end
end


local function best(fg, bg)
	-- todo : make this do no allocation

	-- analyze fg & bg for their contrast
	fg, bg = fg * 255, bg * 255 -- todo : this allocates
	local cieFg = toCIE(fg)
	local cieBg = toCIE(bg)
	local labFg = toLab(cieFg)
	local labBg = toLab(cieBg)
	--local adamsFg = adams(cieFg)
	--local adamsBg = adams(cieBg)
	
	local JND = 2.3 -- just-noticeable-difference
	local areTheSame = CIE76(labFg, labBg) <= JND
	
	local fg1, fg2, fg1_s, fg2_s = 0, 0, 1000000000, 1000000000
	local bg1, bg2, bg1_s, bg2_s = 0, 0, 1000000000, 1000000000

	for i = 0, 7 do
		local s = CIE76(labPalette[i], labBg) + bg_bias[i]
		if s < bg2_s then
			if s < bg1_s then
				bg2, bg1 = bg1, i
				bg2_s, bg1_s = bg1_s, s
			else
				bg2 = i
				bg2_s = s
			end
		end
	end

	if areTheSame then
		return bg1, bg1
	end

	for i = 0, 15 do
		local s = CIE76(labPalette[i], labFg) + fg_bias[i]
		if s < fg2_s then
			if s < fg1_s then
				fg2, fg1 = fg1, i
				fg2_s, fg1_s = fg1_s, s
			else
				fg2 = i
				fg2_s = s
			end
		end
	end
	
	if fg1 ~= bg1 or areTheSame then
		return fg1, bg1
	else
		if fg1_s + bg2_s < fg2_s + bg1_s then
			return fg1, bg2
		else
			return fg2, bg1
		end
	end
end

initialize()

return {
	pair = best
}

