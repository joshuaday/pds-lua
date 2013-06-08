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
#####11111##################111###############111111122111##
#####122221###########1####1221########11111111222222332221#
#####1233321#########11###12321###############1112333443321#
####1234433211111####11###1221###################123454321##
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
####122112321###1222221###123321####111##112321######12321##
####121##12321###1112321#1234321###########1221#######12321#
#####1####12321#####12321234321############1221########1221#
##########12321######1232344321############1221#########11##
#########1234321#####12333333321##########12321#############
#########1233321####123332222222111#####11233321############
##########122221####1222211111122221###12222233211##########
###########1111#####11111######12221####11111222221#########
################################111##########11111##########
############################################################
]]

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
		local grid = Grid.new(width, height, 8)
		local cells = grid:overlay "int"
		
		local point = {x = 1, y = 1}
		for line in lines(src) do
			for x = 1, #line do
				point.x = x
				if string.byte(line, x) == string.byte "#" then
					cells:set(point, -1)
				else
					cells:set(point, 1)
				end
			end
			cells:set(point, -1)
			point.y = point.y + 1
		end

		return grid, cells
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
		{ x = 30, y = 9}
	}

	local time = 0

	local beeping = false

	local grid, cells = stringmap(cave)

	local function beep()
		beeping = 7
	end

	local function interactiveinput()
		local key, code = term.nbgetch()
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

		local input = grid:overlay "int" :fill(300) :set(player, 0)
		local fromplayer = input / cells

		for x, y, idx in grid:lattice() do
			term.at(x - 1, y - 1)
			if cells.cells[idx] == -1 then
				term.fg(0).bg(4).print("#")
				-- term.fg(7).bg(0).put(65 + output.cells[idx])
			else
				term.fg(7).bg(0).print(".")
				-- term.fg(7).bg(0).put(65 + output.cells[idx])
			end
		end
		
		do
			flight = (fromplayer * -2) / cells
			for i = 1, #monsters do
				local monster = monsters[i]
				flight:rolldown(cells, monster)
			end
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

