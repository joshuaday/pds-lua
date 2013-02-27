local ffi = require "ffi"
local coerce = require "coerce"

local hasbold, hasblink = true, true

local black = color(0, 0, 0, 1)

local function getcurses()
	local ncurses = ffi.load("ncurses")

	require "cdefheader"

	-- a table of attributes and colors

	local attr = {
		blink = bit.lshift(1, 8 + 11),
		bold = bit.lshift(1, 8 + 13),
		color = {
			black = 0,
			red = 1,
			green = 2,
			yellow = 3,
			blue = 4,
			magenta = 5,
			cyan = 6,
			gray = 7
		}
	}
	
	local function clean()
		ncurses.erase()
		ncurses.refresh()
		ncurses.endwin()
	end

	os.atexit(clean)

	return ncurses, attr
end


local function adapter()
	local adapter

	local ncurses, attr, extended = getcurses()

	local function initialize()
		local function startcurses()
			local stdscr = ncurses.initscr()
			ncurses.raw()
			ncurses.noecho()
			ncurses.cbreak()
			ncurses.curs_set(0)
			ncurses.scrollok(stdscr, false)
		end

		local function preparecolor()
			if ncurses.has_colors() then
				ncurses.start_color( )
				for bg = 0, 7 do
					for fg = 0, 7 do
						ncurses.init_pair(1 + fg + bg * 8, fg, bg)
					end
				end
			end
		end

		local function startmouse()
			if ncurses.has_mouse and ncurses.has_mouse() then
				-- mousemask( , nil);

				-- getmouse( );
				--[[extern int     getmouse (MEVENT *);
				extern int     ungetmouse (MEVENT *);
				extern mmask_t mousemask (mmask_t, mmask_t *);
				extern bool    wenclose (const WINDOW *, int, int);
				extern int     mouseinterval (int);
				extern bool    wmouse_trafo (const WINDOW*, int*, int*, bool);
				extern bool    mouse_trafo (int*, int*, bool);              /* generated */
				]]
				
			end
		end

		startcurses()
		preparecolor()
		startmouse()
	end

	local nonblocking = false

	local function settitle(title)
		print "\027]2;" -- ESC ]2;
		print (title) 
		print "\007" -- BEL
	end

	local function putch(x, y, ch)
		ncurses.mvaddch(y, x, ch)
	end

	local function nodelay(b)
		b = b or false
		if nonblocking ~= b then
			ncurses.nodelay(ncurses.stdscr, b)
			nonblocking = b
		end
	end

	local function getch(noblock)
		nodelay(noblock)

		do
			local ch = ncurses.getch()
			if ch > 0 and ch < 256 then
				return string.char(ch), ch
			end
		end
	end
	
	local function getms()
		--struct timeb time;
		--ftime(&time);
		--return 1000 * time.time + time.millitm;
		return 15
	end

	local current_attr = -1
	local function color4(fg, bg)
		local color = ncurses.COLOR_PAIR(1 + bit.band(7, fg) + 8 * bit.band(7, bg))

		if hasbold and fg > 7 then
			color = bit.bor(color, attr.bold)
		end
		if hasblink and bg > 7 then
			color = bit.bor(color, attr.blink)
		end
		if color ~= current_attr then
			ncurses.attrset(color)
			current_attr = color
		end
	end
	local function color32(fg, bg)
		fg, bg = coerce.pair(fg, bg)
		color4(fg, bg)
	end

	local aspect = .5
	local function getsize()
		return ncurses.COLS, ncurses.LINES, aspect
	end

	initialize()

	adapter = {
		color4 = color4,
		color32 = color32,
		putch = putch,
		getch = getch,
		getsize = getsize,
		refresh = ncurses.refresh,
		erase = ncurses.erase,
		endwin = ncurses.endwin,
		napms = ncurses.napms,
		getms = getms,
		settitle = settitle
	}
	
	return adapter
end

return adapter()


