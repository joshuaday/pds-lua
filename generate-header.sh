#! /usr/bin/env bash

# uses the gnu C preprocessor to generate an input to LuaJIT's ffi
# grep is used to remove all preprocessor directives from the output,
# which will otherwise trip up LuaJIT.

cpp <<- eof | grep ^[^#] > shared-header.h
	#include <time.h>
	#include <sys/types.h>
	#include <sys/stat.h>
	#include <dirent.h>
	#include <ncurses.h>
eof

