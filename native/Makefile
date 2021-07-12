#
# Copyright (c) 2026, Nexus Distributed Data Grid Authors
# Licensed under the Apache License, Version 2.0
#

CC ?= clang
CFLAGS ?= -O3 -Wall -Wextra -pedantic -std=c99 -Iinclude -fPIC
UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
    SHLIB_EXT := dylib
    SHLIB_FLAGS := -dynamiclib
else
    SHLIB_EXT := so
    SHLIB_FLAGS := -shared
endif

TARGET_LIB := libnexus_accel.$(SHLIB_EXT)
TARGET_TEST := test_runner

all: $(TARGET_LIB) $(TARGET_TEST)

$(TARGET_LIB): src/nexus_accel.c
	$(CC) $(CFLAGS) $(SHLIB_FLAGS) -o $@ $^

$(TARGET_TEST): test/nexus_accel_test.c src/nexus_accel.c
	$(CC) $(CFLAGS) -o $@ $^

test: $(TARGET_TEST)
	./$(TARGET_TEST)

clean:
	rm -f $(TARGET_LIB) $(TARGET_TEST) *.o

.PHONY: all test clean
