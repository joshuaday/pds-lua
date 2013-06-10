
local term = require "terminal"
local pds = require "pds/pds"

local compass = {
	h = {-1, 0},
	j = {0, 1},
	k = {0, -1},
	l = {1, 0},
	y = {-1, -1},
	u = {1, -1},
	b = {-1, 1},
	n = {1, 1}
}

term.settitle "Progressive Dijkstra Scan"



local cave = [[
############################################################
#####################################################11#####
#####11111##################111###~~~~~~######111111122111##
#####122221###########1####1221~~~~~~~~11111111222222332221#
#####1233321#########11###12321~~~~~~~~#######1112333443321#
####1234433211111####11###1221##~~~~~~###########123454321##
###123443223222221###1####121####################12344321###
##12344321123333321##1####121####################12344321###
##1234321##122234321#1###12321##################123454321###
##123321####1112343211##1234321################12345654321##
##12211########12343221123454321#######11######12334554321##
##111###########1233222223454321######121#######1223454321##
#########11######12211111234321######1221########11234321###
########122111111111#####123321#####12321##########123321###
#######123321#############123321111123321###########12321###
#######1234321############123321###1234321###########12321##
#######1234321###########1234321###1234321###########12321##
######1234321####11######1234321####1234321#########123321##
#####1233321####1221#####1234321####123223211111111123321###
####12322321####123211####123321####12211222221#####12321###
####122112321###1222221###123321#~~~111##112321######12321##
####121##12321###1112321#1234321#~~~~~#####1221#######12321#
#####1####12321#####12321234321##~~~~~~####1221########1221#
##########12321######1232344321###~~~~~####1221#########11##
#########1234321#####12333333321##########12321#############
#########1233321####123332222222111#####11233321############
##########122221####1222211111122221###12222233211##########
###########1111#####11111######12221####11111222221#########
################################111##########11111##########
############################################################
]]

local tiletype = {
	[string.byte "."] = { fg = 7, bg = 0, ch = ".", cost = 1 },
	[string.byte "#"] = { fg = 0, bg = 4, ch = "#", block = 1 },
	[string.byte "~"] = { fg = 2, bg = 0, ch = "~", cost = 1 }
}

local function stringmap(src)

	local function lines(src)
		local idx = 1
		return function ()
			local i1, i2 = string.find(src, "[^\010\013]+", idx)
			
			if i1 == nil then
				return nil
			end

			idx = 1 + i2
			
			return string.sub(src, i1, i2)
		end
	end

	local width, height = 0, 0
	for line in lines(src) do
		height = height + 1
		width = math.max(width, #line)
	end
	
	if width > 0 and height > 0 then
		-- allocate a topology and wall overlay for the map
		local Grid = require "pds/topo/grid"
		local grid = Grid.new(width, height, 6)
		local cells = grid:overlay "int"
		local mask = grid:overlay "int"
		local costs = grid:overlay "int"
		
		local point = {x = 1, y = 1}
		for line in lines(src) do
			for x = 1, #line do
				local c = string.byte(line, x)

				point.x = x
				if not tiletype[c] then c = string.byte "." end
				cells:set(point, c)

				costs:set(point, tiletype[c].cost or -1)
				mask:set(point, tiletype[c].block or 0)
			end
			point.y = point.y + 1
		end

		return grid, cells, costs
	end
end


local function simulate(term)
	local command = nil
	local hasquit = false
	local paused = false

	local player = { x = 5, y = 5 }
	local monsters = {
		{ x = 50, y = 6},
		{ x = 20, y = 6},
		{ x = 40, y = 4},
		{ x = 10, y = 7},
		{ x = 30, y = 8},
		{ x = 20, y = 16},
		{ x = 30, y = 9},

		{ x = 50, y = 7},
		{ x = 20, y = 7},
		{ x = 40, y = 7},
		{ x = 10, y = 8},
		{ x = 30, y = 9},
		{ x = 20, y = 17},
		{ x = 30, y = 10}
	}

	local time = 0

	local beeping = false

	local grid, cells, costs = stringmap(cave)

	local function beep()
		beeping = 7
	end

	local function interactiveinput()
		local key, code = term.getch()
		-- playerturn(player, key)

		if key == "Q" then
			hasquit = true
			return
		end

		if key ~= nil then
			local lowerkey = string.lower(key)
			local dir = compass[lowerkey]
			
			if dir ~= nil then
				-- world.feed(dir[1], dir[2])
				if key >= "A" and key <= "Z" then
			--
				end
				player.x, player.y = player.x + dir[1], player.y + dir[2]
			end

			if key == "p" then paused = not paused end
		end
	end

	repeat
		-- rotinplace(screen[1], screen[3], .001)
		interactiveinput()

		term.erase()
		term.clip(0, 0, nil, nil, "square")
		--world.draw(term, beeping)
		--world.advance( )

		--term.fg(15).bg(0).at(1, 1).print(globe.formattime())

		if type(beeping) == "number" then
			beeping = beeping - 1
			if beeping < 1 then
				beeping = false
			end
		end


		local input = grid:overlay "int" :fill(200) :set(player, 0)

		for i = 1, #monsters do
			local monster = monsters[i]
			costs:set(monster, 1) -- monsters should walk around each other if it'll only take two extra turns
		end

		local fromplayer = input / costs

		do
			local prev = costs:get(player)
			costs:set(player, -1)
			flight = (fromplayer * -2) / costs
			-- flight:mul(2):add(fromplayer, -1)

			for i = 1, #monsters do
				local monster = monsters[i]
				costs:set(monster, -1)
			end

			for i = 1, #monsters do
				local monster = monsters[i]

				costs:set(monster, 1)
				flight:rolldown(costs, monster)
				costs:set(monster, -1)
			end
			costs:set(player, prev)
		end



		for x, y, idx in grid:lattice() do
			term.at(x - 1, y - 1)
			local c = cells.cells[idx]
			local tile = tiletype[c]
			
			term.fg(tile.fg).bg(tile.bg).print(tile.ch)
		end

		term.at(player.x - 1, player.y - 1).fg(15).bg(0).print("@")
		for i = 1, #monsters do
			local monster = monsters[i]
			term.at(monster.x - 1, monster.y - 1).fg(15).bg(0).print("m")
		end

		local w, h = term.getsize() -- current "square" terminal
		term.clip(w, 0, nil, nil)
		
		term.clip()

		term.refresh()
		term.napms(15)
	until hasquit
end

simulate(term)

term.erase()
term.refresh()
term.endwin()

