.PHONY: all
all: native/space-mover

native/space-mover: native/main.m native/WindowSpaceMove.c native/WindowSpaceMove.h
	xcrun clang -O2 -Wall -Wextra -fblocks -framework AppKit -framework CoreFoundation native/main.m native/WindowSpaceMove.c -o $@
