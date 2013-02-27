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

local function simulate(term)
	local command = nil
	local hasquit = false
	local paused = false

	local time = 0

	local beeping = false

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

