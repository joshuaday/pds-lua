local ffi = require "ffi"
local layer = require "pds/layer"

local pqueue = require "pds/pqueue"


local pq = pqueue.new()

pq:insert(5, 20)
pq:insert(7, 12)

print (pq:pop())

