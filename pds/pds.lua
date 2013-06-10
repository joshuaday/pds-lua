local ffi = require "ffi"

--local Heap = require "pds/heap"
local Heap = require "pds/pqueue"

local PDS = { }

function PDS.bestneighbor(map, costs, idx)
	local target = idx
	if idx > 0 then
		local edgemap = map.topology:edgemap_from_costmap(costs)
		local min = map.cells[idx]
		local owntime = 0

		local state = 0
		local neighbor, posterior

		while true do
			neighbor, posterior, state = edgemap:outlet(idx, owntime, state)
			if neighbor == nil then
				break
			end
			local actual_neighbor_cost = map.cells[neighbor]
			if actual_neighbor_cost < min or target == idx then
				target, min = neighbor, actual_neighbor_cost
			end
		end
	end

	return target
end

function PDS.dijkstra(costmap, output, initial)
	local heap = Heap.new()

	local max = initial:fold(math.max)
	
	initial:each(function (prior, idx) 
		if prior < max and costmap.cells[idx] >= 0 then
			heap:push(idx, prior)
		end
	end)

	output:copyfrom(initial)

	if not heap:isempty() then
		local edgemap = initial.topology:edgemap_from_costmap(costmap)

		-- remember: costs here are negative for implementation details yeah
		while not heap:isempty() do
			local idx, prior = heap:pop()

			-- prior = -prior

			if output.cells[idx] == prior then
				local state = 0
				local neighbor, posterior

				while true do
					neighbor, posterior, state = edgemap:outlet(idx, prior, state)
					if neighbor == nil then
						break
					end
					
					-- compare the new cost to the current cost in the cell (inefficient, meh)
					local oldscore = output.cells[neighbor]

					if oldscore > posterior then
						output.cells[neighbor] = posterior
						if posterior < max then
							heap:push(neighbor, posterior)
						end
					end
				end
			end
		end
	end
end

return PDS

