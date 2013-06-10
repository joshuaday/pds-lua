
local Tests = { }
local fail = print

function Tests.topology(topo)
	local function test_index()
		print "Testing index/deindex..."
		local p = { }
		for i = 1, topo.length do
			topo:deindex(p, i)
			if topo:index(p) ~= i then
				fail(" Index mismatch at i == " .. i)
			end
		end
	end

	test_index()
end

return Tests

