.PHONY: build run clean verify

build:
	sh Scripts/build.sh

run: build
	open build/YoungBar.app

verify:
	sh Scripts/verify.sh

clean:
	rm -rf .build build
