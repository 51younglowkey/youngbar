# SPDX-FileCopyrightText: 2026 YoungBar contributors
# SPDX-License-Identifier: GPL-3.0-only

.PHONY: build run clean verify package

build:
	sh Scripts/build.sh

run: build
	open build/YoungBar.app

verify:
	sh Scripts/verify.sh

package:
	sh Scripts/package.sh

clean:
	rm -rf .build build
