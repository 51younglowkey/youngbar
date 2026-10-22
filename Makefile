# SPDX-FileCopyrightText: 2026 YoungBar contributors
# SPDX-License-Identifier: GPL-3.0-only

.PHONY: build run clean verify

build:
	sh Scripts/build.sh

run: build
	open build/YoungBar.app

verify:
	sh Scripts/verify.sh

clean:
	rm -rf .build build
