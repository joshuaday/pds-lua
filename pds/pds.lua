local ffi = require "ffi"

--local Heap = require "pds/heap"
local Heap = require "pds/pqueue"

local PDS = { }

function PDS.bestneighbor(map, costs, idx)
	local target = idx
	if idx > 0 then
		local topology = map.topology
		local min = map.cells[idx]
		local owntime = 0

		local state = 0
		local neighbor, posterior

		while true do
			neighbor, posterior, state = topology:neighbor(idx, costs, owntime, state)
			if neighbor == nil then
				break
			end
			local actual_neighbor_cost = map.cells[neighbor]
			if actual_neighbor_cost < min then
				target, min = neighbor, actual_neighbor_cost
			end
		end
	end

	return target
end

function PDS.dijkstra(costmap, output, initial)
	local heap = Heap.new()
	local topology = initial.topology

	initial:each(function (prior, idx) 
		if costmap.cells[idx] >= 0 then
			heap:push(idx, prior)
		end
	end)

	output:copyfrom(initial)

	-- remember: costs here are negative for implementation details yeah
	while not heap:isempty() do
		local idx, prior = heap:pop()

		-- prior = -prior

		if output.cells[idx] == prior then
			local state = 0
			local neighbor, posterior

			while true do
				neighbor, posterior, state = topology:neighbor(idx, costmap, prior, state)
				if neighbor == nil then
					break
				end
				
				-- compare the new cost to the current cost in the cell (inefficient, meh)
				local oldscore = output.cells[neighbor]

				if oldscore > posterior then
					output.cells[neighbor] = posterior
					heap:push(neighbor, posterior)
				end
			end
		end
	end
end

return PDS

