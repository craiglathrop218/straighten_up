.PHONY: build run clean test

build:
	swift build -c release
	mkdir -p build
	cp .build/release/StraightenUp build/StraightenUp

run: build
	./build/StraightenUp $(ARGS)

clean:
	swift package clean
	rm -rf build

test:
	swift run StraightenUpTests
