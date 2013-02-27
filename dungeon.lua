local ffi = require "ffi"
local tiles = require "tiles"
local mobs = require "mobs"
local fov = require "fov"
local generator = require "generator"
local random = require "random"
local arbiter = require "tick"

local color = color
local black = color(0,0,0,0)

ffi.cdef [[
	typedef struct {
		int ch;
		color fg, bg;
		bool fg_normal, bg_normal; // components may be separately omnidirectional

		int movement;  // 0 = open, 1 = blocked by something mobile, 2 = blocked
		int diagonal; // 0 = no effect, 1 = no squeezing, 2 = no skirting at all

		color transparency; // {1.0, 1.0, 1.0} is totally clear
		
		color lit_fg, lit_bg; // accumulator for all lighting effects 
		bool dirty; // tracks whether updates are necessary
		bool dirty_fov; // tracks whether updates are necessary for nearby lights

		float heat, smoke;
		int animtype;
		
		float normal[3];
	} cell_summary;
]]

local cell_summary = ffi.metatype("cell_summary", {
	__index = {
		wipe = function(a)
			a.movement = 0
			a.diagonal = 0
			a.ch = 0
			a.fg = color(0, 0, 0)
			a.bg = color(0, 0, 0)
			a.fg_normal = true
			a.bg_normal = true
			a.transparency = color(1, 1, 1)
			a.dirty = false
			a.animtype = 0
		end,
		stack = function(a, b) 
			if b.ch then a.ch = b.ch end
			if b.fg then a.fg:stack(b.fg) end
			if b.bg then a.bg:stack(b.bg) end
			if b.heat and b.heat > a.heat then a.heat = b.heat end
			if b.vertical then
				a.fg_normal = false
				if b.bg.a > 0.5 then -- todo : this sucks
					a.bg_normal = false
				end
			end
			if b.movement > a.movement then
				a.movement = b.movement
			end
			if b.diagonal > a.diagonal then
				a.diagonal = b.diagonal
			end
			if b.animtype and b.animtype > a.animtype then
				a.animtype = b.animtype
			end
			a.transparency = a.transparency * b.transparency
		end
	}
})

local function animate(camera)
	local level = camera.follow.level

	local height, vx, vy
	if level.animation then
		height, vx, vy = level.animation.height, level.animation.vx, level.animation.vy
	else
		height, vx, vy = 
			tiles.layer("float", level.width, level.height),
			tiles.layer("float", level.width + 1, level.height),
			tiles.layer("float", level.width, level.height + 1)

		level.animation = {
			height = height,
			vx = vx,
			vy = vy
		}
		
		height.setdefault(0)
		
		vx.setdefault(0)
		vx.fill(0)
		vy.setdefault(0)
		vy.fill(0)
	end

	local function waves()
		local dt = .13
		local a = dt * .6
		local damp = .990
		local info = level.info

		-- adjust flow
		vx.each(function(v, x, y)
			-- if either neighboring cell is non-water, go to 0
			local w, e = info(x - 1, y).animtype, info(x, y).animtype
			if w == 1 and e == 1 then
				local hw, he = height.get(x - 1, y), height.get(x, y)
				vx.set(x, y, damp * (v + a * (hw - he)))
			else
				vx.set(x, y, 0)
			end
		end)

		vy.each(function(v, x, y)
			-- if either neighboring cell is non-water, go to 0
			local n, s = info(x, y - 1).animtype, info(x, y).animtype
			if n == 1 and s == 1 then
				local hn, hs = height.get(x, y - 1), height.get(x, y)
				vy.set(x, y, damp * (v + a * (hn - hs)))
			else
				vy.set(x, y, 0)
			end
		end)

		-- add flow
		level.each(function(info, x, y)
			-- if the cell has a water visualization type, propagate it
			if info.animtype == 1 then
				local h = height.get(x, y)
				local vn, vs, vw, ve = vy.get(x, y), -vy.get(x, y + 1), vx.get(x, y), -vx.get(x + 1, y)
				
				height.set(x, y, h + dt * (vn + vw + vs + ve))
			end
		end)
	end
	
	-- todo : let's merge this with compute_normals in generator.lua?
	local function compute_normals(camera, height)
		local CELL_SIZE = 1
		camera.normals.each(function(normal, x, y)
			local hn, hs, hw, he =
				height.get(x, y - 1), height.get(x, y + 1), 
				height.get(x - 1, y), height.get(x + 1, y)
			-- todo -- ignore e/w or n/s or both when neighbors have the wrong animtype

			local ddx = -.5 * (he - hw)
			local ddy = -.5 * (hs - hn)

			local normalsize = 1.0 / math.sqrt(ddx * ddx + ddy * ddy + CELL_SIZE * CELL_SIZE)

			normal[0], normal[1], normal[2] = 
				ddx * normalsize,
				ddy * normalsize,
				CELL_SIZE * normalsize
		end)
	end

	local function droplet()
		local x, y = random.range(0, level.width - 2), random.range(0, level.height - 2)
		if x >= camera.x1 and x < camera.x1 + camera.width and y >= camera.y1 and y < camera.y1 + camera.height then
			return
		end
		height.set(x, y, .1 + height.get(x, y))
		height.set(x+1, y, .1 + height.get(x+1, y))
		height.set(x, y+1, .1 + height.get(x, y+1))
		height.set(x+1, y+1, .1 + height.get(x+1, y+1))
	end
	

	if random.unit < .1 then droplet() end

	camera.normals.moveto(camera.x1, camera.y1)
	waves()
	compute_normals(camera, height)
	
	camera.eye = {camera.x1 + .5 * camera.width, camera.y1 + 1.5 * camera.height, 55}
	--camera.eye = {level.width * .5, level.height + 3, 15}
end

local function new_level(width, height)
	local self

	local cells, summaries = { }, ffi.new("cell_summary[?]", width * height + 1)
	local memory = tiles.layer("color", width, height)
	
	local tickers, lights, fovs, inject_below = { }, { }, { }, { }
	
	local count = width * height
	local locked = false
	local dirty = true
	
	local function new_cell()
		-- the array part of a cell contains all fixed features
		-- normally [1] for floor, [2] for foliage or whatever;
		-- the hash part is for other arbitrary stuff like:
		--  mob, item, 
		return { }
	end

	local function commit_cell(cell, summary)
		summary:wipe()
		
		for i = 1, #cell do
			summary:stack(cell[i])
		end
	end

	local function summarize()
		if not dirty then
			return
		else
			for i = 1, count do
				local summary = summaries[i]
				if summary.dirty then
					commit_cell(cells[i], summary)
				end
			end
			dirty = false
		end
		return self
	end

	local function index(x, y)
		if x == nil or x < 1 or y < 1 or x > width or y > height then
			return 0
		else
			return x + (y - 1) * width
		end
	end

	local function render(term, camera)
		local start = term.getms() -- I don't want getms on term

		local w, h = term.getsize()
		local fov, x1, y1 = camera.fov, camera.x1, camera.y1

		animate(camera)
		local eye = camera.eye

		local sunorth, bmp
		
		local sky = camera.follow.level.sky
		if sky ~= nil then
			bmp = sky.bmp
			sunorth = inplace.normalize {sky.sun[1], sky.sun[2], 0}
		end

		local fgc, bgc = color(0, 0, 0, 1), color(0, 0, 0, 1)

		for y = 0, h - 1 do
			for x = 0, w - 1 do
				local fov_color = fov.get(x + x1, y + y1)

				-- todo make these more exact, or include an alpha component for % visible
				-- also, stop allocating so much
				local summary = summaries[index(x + x1, y + y1)]

				fgc:set(summary.lit_fg)
				bgc:set(summary.lit_bg)

				if summary.animtype ~= 0 then
					-- do light reflection from the eye perspective (how to check whether this is appropriate?)
					local sight = {(x + x1) - eye[1], (y + y1) - eye[2], -eye[3]}
					local normal = camera.normals.get(x + x1, y + y1)
					local bounce = 2 * (sight[1] * normal[0] + sight[2] * normal[1] + sight[3] * normal[2])

					local reflect = inplace.normalize {sight[1] - bounce * normal[0], sight[2] - bounce * normal[1], sight[3] - bounce * normal[2]}
					local skycolor = self.sky_lookup(reflect)

					fgc:add(skycolor, 1.0) -- todo: compute this from something?
					bgc:add(skycolor, 1.0)
				end

				fgc:mul(fov_color)
				bgc:mul(fov_color)

				term
					.at(x, y)
					.fg(fgc).bg(bgc)
					.put(summary.ch)
			end
		end

		print("Rendering: " .. (term.getms() - start) .. "ms")
		return self
	end
	
	local function initialize( )
		dirty = true
		up = {0, 0, 1}
		cells[0] = setmetatable ({ }, {__newindex = function() end})
		for i = 1, count do
			cells[i] = { }
			summaries[i].dirty = true
			summaries[i].dirty_fov = true

			summaries[i].normal = up

			summaries[i].heat = 0
			summaries[i].smoke = 0
		end
		summaries[0] = cell_summary(tiles.types.out_of_bounds)

		memory.fill(color(0,0,0,0))
		memory.setdefault(color(0,0,0,0))
	end

	local function clone(feature)
		-- just a shallow table clone for now, but it leaves options open
		local feat = { }
		for k, v in pairs(feature) do
			if k ~= "template" then
				feat[k] = v
			end
		end

		if feat.range then
			local v = feat.range
			feat.fov = tiles.layer("color", 1 + v * 2, 1 + v * 2) 
			feat.fov.setdefault(color(0, 0, 0, 0))
			feat.mask = fov.mask.circle(v)

			if feat.light then
				feat.light = color(feat.light.r, feat.light.g, feat.light.b, feat.light.a)
				-- set attenuation to fall off smoothly near the edge of the radius?
			end
		end

		return feat
	end

	local function remove_partial(feature)
		local x, y = feature.x, feature.y
		local idx = index(x, y)
		if idx > 0 then
			if not feature.transparency:iswhite() then
				summaries[idx].dirty_fov = true
			end

			local cell = cells[idx]
			for i = 1, #cell do
				if cell[i] == feature then
					-- we expect these feature lists to be quite short
					table.remove(cell, i)
					break
				end
			end

			if locked then
				summaries[idx].dirty = true
				dirty = true
			else
				commit_cell(cells[idx], summaries[idx])
			end
		end
	end

	local function remove(feature)
		if feature.light then
			lights[feature] = nil
		end
		if feature.fov then
			fovs[feature] = nil
		end
		if feature.tick then
			feature.removed = true
		end
		remove_partial(feature)

		return self
	end
	
	local function add(x, y, feature)
		-- feature will be cloned unless feature.unique == true
		-- (if feature.unique is true and the feature is already on the map,
		--  it will first be removed.)

		x, y = math.floor(x), math.floor(y)
		local idx = index(x, y)

		if idx == 0 then
			if feature.x ~= nil then
				remove(feature)
				feature.x, feature.y = nil, nil
				return feature
			else
				return nil
			end
		end

		if feature.template then
			feature = clone(feature)
		else
			if feature.level and feature.level ~= self then
				feature.level.remove(feature)
			else
				remove_partial(feature)
			end
		end

		feature.x, feature.y = x, y

		-- not sure if I want to use this trick, really
		if feature.light then
			lights[feature] = true
		end
		if feature.fov then
			fovs[feature] = true
			feature.dirty_fov = true
		end
		if feature.tick then
			if not feature.removed then
				tickers[1 + #tickers] = feature
			else
				feature.removed = false
			end
			feature.level = self
		end

		if feature.inject_below then
			inject_below[1 + #inject_below] = feature
		end
		
		local cell = cells[idx]
		local i, target = 1, 0

		-- remove similar things and decide where to insert it
		while i <= #cell do
			local feat_in_cell = cell[i]
			-- todo check whether they're both floors, walls, etc, and remove them safely
			if feat_in_cell.priority < feature.priority then
				target = i
			end
			i = i + 1
		end

		table.insert(cell, target + 1, feature)
		if not feature.transparency:iswhite() then
			summaries[idx].dirty_fov = true
		end

		if locked then
			summaries[idx].dirty = true
			dirty = true
		else
			commit_cell(cell, summaries[idx])
		end

		return feature
	end

	local function each(f)
		local i = 1
		for y = 1, height do
			for x = 1, width do
				f(summaries[i], x, y)
				i = i + 1
			end
		end
		return self
	end

	local function on_edge(x, y)
		return x == 1 or y == 1 or x == width or y == height
	end

	local function info(x, y)
		return summaries[index(x, y)]
	end
	
	local function stacked_features(x, y)
		return cells[index(x, y)]
	end

	local function can_move(x, y, dx, dy, thresh)
		if thresh == nil then thresh = 1 end
		if info(x + dx, y + dy).movement < thresh then
			if dx ~= 0 and dy ~= 0 then
				-- diagonal!
				return (info(x+dx, y).diagonal + info(x, y+dy).diagonal) < 2
			else
				-- cardinal!
				return true
			end
		else
			-- blocked!
			return false
		end
	end
	
	local function remember(fov)
		local cells, index = memory.cells, memory.index
		function max(c, x, y)
			local idx = index(x, y)
			if idx ~= 0 then
				cells[idx]:max(c)
			end
		end
		fov.each(max)
	end

	local function relight(term)
		-- might want bounds on this (very likely, in fact)

		-- first, get new fov scans for all lights

		do
			local start = term.getms()
			local ct = 0
			for source in pairs(fovs) do
				-- be aware that mobs with lights will be scanned only once

				if not source.dirty_fov then
					local fov = source.fov
					local x1, x2 = fov.x1, fov.x1 + fov.width - 1
					local cells = fov.cells

					local i = 1
					for y = fov.y1, fov.y1 + fov.height - 1 do
						for x = x1, x2 do
							local idx = index(x, y) -- could clip other ways
							if idx ~= 0 and summaries[idx].dirty_fov then
								-- make sure it was in fov previously --
								if not cells[i]:isblack() then
									source.dirty_fov = true
									break
								end
							end
							i = i + 1
						end
						if source.dirty_fov then break end
					end
				end
				
				if source.dirty_fov then
					source.fov.recenter(source.x, source.y)
					fov.scan(self, source.fov, source.x, source.y, source.mask)
					source.dirty_fov = false
					ct = ct + 1
				end
			end
			print("FOV:   " .. (term.getms() - start) .. "ms" .. " (" .. ct .. ")")
		end

		-- second, wipe all lights to ambience
		local start = term.getms()
		do
			local i = 1
			local ambience, sun, sunorth, shine, bmp = black, nil, nil, nil, nil
			
			local sky = self.sky
			if sky ~= nil then
				ambience, sun, shine, bmp = sky.ambience, sky.sun, sky.shine, sky.bmp
				
				sunorth = inplace.normalize {sun[1], sun[2], 0}
			end

			for y = 1, height do
				for x = 1, width do
					local info = summaries[i]

					info.lit_fg:set(ambience)
					info.lit_bg:set(ambience)
					info.dirty_fov = false

					local c = self.sky_lookup(info.normal) -- todo : add a diffusion map
					info.lit_fg:add(c, 1)
					info.lit_bg:add(c, 1)

					i = i + 1
				end
			end
		end
		
		-- third, loop over all lights and contribute
		local lightct = 0
		do
			for source in pairs(lights) do
				local fov, lc = source.fov, source.light
				local cells = fov.cells
				local x1, x2 = fov.x1, fov.x1 + fov.width - 1
				local lx, ly = source.x, source.y
				local dz = source.height or 1
				local attenuation = source.light.a

				local i = 1

				lightct = lightct + 1
				for y = fov.y1, fov.y1 + fov.height - 1 do
					for x = x1, x2 do
						local idx = index(x, y) -- could clip other ways
						if idx ~= 0 then
							-- this, I dislike mightily
							local info = summaries[idx]
							local n = info.normal

							local dx, dy = x - lx, y - ly

							local dot = (dx * n[0] + dy * n[1] + dz * n[2])
							local d2 = (attenuation + dx * dx + dy * dy) / attenuation
							local scale = dot / d2

							if dot < 0 then dot = 0 end

							-- this branching is very costly -- more costly than the arithmetic
							if info.fg_normal then
								info.lit_fg:add_mul(lc, cells[i], dot / d2)
							else
								info.lit_fg:add_mul(lc, cells[i], 1 / math.sqrt(d2))
							end
							if info.bg_normal then
								info.lit_bg:add_mul(lc, cells[i], dot / d2)
							else
								info.lit_bg:add_mul(lc, cells[i], 1 / math.sqrt(d2))
							end
						end
						i = i + 1
					end
				end
			end
		end
		
		-- fourth, loop over all cells and finalize
		do
			local i = 1
			for y = 1, height do
				for x = 1, width do
					local info = summaries[i]
					info.lit_fg:mul(info.fg)
					info.lit_bg:mul(info.bg)

					i = i + 1
				end
			end
		end
		print("Lights: " .. (term.getms() - start) .. "ms (" .. (lightct) .. ")")
	end

	local function tick(term)
		local start = term.getms()
		local oldtickers
		oldtickers, tickers = tickers, { }
		arbiter.tick(self, oldtickers, tickers)
		relight(term) -- needs term so it can use getms
		print ("Tick: " .. term.getms() - start .. "ms")
	end

	local function lock()
		locked = true
	end
	local function unlock()
		locked = false
		summarize()
	end
	
	initialize( )
	
	self = {
		index = index,
		info = info,
		stacked_features = stacked_features,
		add = add,
		each = each,
		remove = remove,
		width = width,
		height = height,
		render = render,
		tick = tick,
		summarize = summarize,
		
		lock = lock,
		unlock = unlock,

		-- utilities:
		on_edge = on_edge,
		can_move = can_move,	
		
		-- raw data:
		summaries = summaries,
		memory = memory,

		-- uncertain provenance:
		relight = relight,
		remember = remember,
		inject_below = inject_below
	}

	return self
end



-- I'd like to offload this to some other descriptor
local levels = { }
local function get_level(n)
	local level = levels[n]
	if level == nil then
		level = new_level(50, 35)
		level.sky_lookup, level.sky_color = function(n)
			return level.sky_color
		end, color (0, 0, 0, 1)
		if n == 1 then
			generator.entry(level)
			level.name = "Above ground"
		elseif n > 1 then
			level.up = get_level(n - 1)

			generator.terrible(level)
			if n == 2 then
				level.name = "Basement"
			else
				level.name = "Depth: " .. (n - 1)
			end
		else
			return get_level(1)
		end
		level.depth = n
		levels[n] = level
	end

	return levels[n]
end

local function tick(term, team)
	local levels = { }
	for i = 1, #team do
		levels[team[i].level] = true
	end
	for level in pairs(levels) do
		level.tick(term)
	end
end

return {
	depth = get_level,
	tick = tick
}

