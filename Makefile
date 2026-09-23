.PHONY: build unit panel live test install cert cert-uninstall clean

build:
	./build.sh

unit:
	mkdir -p build
	swiftc -swift-version 5 -O app/Core/*.swift tests/unit/*.swift -o build/unit && TRISPLIT_REPO=$(CURDIR) build/unit

panel:
	mkdir -p build
	swiftc -swift-version 5 -O -framework AppKit -framework WebKit tests/panel_runner.swift -o build/panel_runner && build/panel_runner panel.html tests/panel_tests.js

live: build
	./Trisplit.app/Contents/MacOS/Trisplit --selftest-live

test: unit panel

install: build
	rm -rf ~/Applications/Trisplit.app
	ditto --norsrc --noextattr Trisplit.app ~/Applications/Trisplit.app
	codesign --verify --deep --strict ~/Applications/Trisplit.app

cert:
	scripts/dev-cert.sh

cert-uninstall:
	scripts/dev-cert.sh --uninstall

clean:
	rm -rf build Trisplit.app
