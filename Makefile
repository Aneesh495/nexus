#
# Copyright (c) 2026, Nexus Distributed Data Grid Authors
# Licensed under the Apache License, Version 2.0
#

.PHONY: all build test test-native test-python test-all lint benchmark server cli clean

all: lint build test-native

lint:
	python3 scripts/verify_no_em_dashes.py .

build:
	fan build.fan

test: build
	fant nexus

test-native:
	$(MAKE) -C native test

test-python:
	pytest tests/

test-all: lint test test-native test-python
	@echo "All test suites (Fantom, Native C, Python) passed cleanly!"

benchmark: build
	fan nexus::NexusBenchmark -n 50000

server: build
	fan nexus::NexusServerMain -p 6379

cli: build
	fan nexus::NexusCli -p 6379

clean:
	$(MAKE) -C native clean
	rm -rf .pytest_cache
	rm -rf python/__pycache__
	rm -rf tests/__pycache__
