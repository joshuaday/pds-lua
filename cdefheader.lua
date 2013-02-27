local ffi = require "ffi"

local headerfile = io.open("shared-header.h", "r")
if not headerfile then
	os.execute("./generate-header.sh")
	headerfile = io.open("shared-header.h", "r")
end
if not headerfile then
	error "generate-header.sh apparently failed to produce a usable header"
end

ffi.cdef (headerfile:read("*all"))


