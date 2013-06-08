
local pqueue = { }
local pqueue_mt = { __index = pqueue }

local function unlink(link)
	local prev, next = link[4], link[3]
	if next ~= nil then
		next[1] = next[1] - link[1]
		next[4] = prev
	end
	prev[3] = next
end

function pqueue:remove(item)
	local link = self.links[item]
	if link ~= nil then
		unlink(link)
	end
	return link
end

function pqueue:push(item, cost)
	local link = self:remove(item) 
	if link == nil then
		link = {cost, item, link, link}
		self.links[item] = link
	end

	local prev, next = self.head, self.head[3]
	while next ~= nil and next[1] <= cost do
		prev = next
		next = prev[3]
		-- cost = cost - prev[1]
	end
	link[1] = cost
	link[4] = prev
	link[3] = next
	prev[3] = link
	if next ~= nil then
		-- next[1] = next[1] - cost
		next[4] = link
	end

	return self
end

function pqueue:pop( )
	local first = self.head[3]
	if first then
		local item, cost, next = first[2], first[1], first[3]
		self.head[3] = next
		if next ~= nil then
			next[4] = self.head
		end
		self.links[item] = nil
		return item, cost
	else
		return nil
	end
end

function pqueue:cheapestcost( )
	local first = self.head[3]
	if first then
		return first[1]
	end
end

function pqueue:cheapen(amt)
	local first = self.head[3]
	if first ~= nil then
		local cheap = first[1]
		if amt == nil or cheap < amt then
			amt = cheap
		end
		first[1] = first[1] - amt
	end

	return amt
end

function pqueue:test(cb)
	local link = self.head[3]
	local all = true
	while link ~= nil and link[1] == 0 do
		all = all and cb(link[2])
		link = link[3]
	end
	return all
end

function pqueue:lookup(item)
	local link = self.links[item]
	if link ~= nil then
		return link[1]
	end
end

function pqueue:isempty()
	return self.head[3] == nil
end


local function newpqueue( )
	return setmetatable({
		head = {nil, nil, nil, nil}, -- deltacost, item, next, prev
		links = { }
	}, pqueue_mt)
end

return {
	new = newpqueue
}

