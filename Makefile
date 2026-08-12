.PHONY: help icon build package zip dmg notarize release clean version sign

APP := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" ClipboardManager/Resources/Info.plist 2>/dev/null)

help:
	@echo "Windows V — distribution toolchain"
	@echo ""
	@echo "  make icon        regenerate all AppIcon sizes + WindowsV.icns from icon/AppIcon.svg"
	@echo "  make build       build Release app -> dist/Windows V.app"
	@echo "  make package     create dist/WindowsV-$(APP).zip and .dmg (alias: make zip, make dmg)"
	@echo "  make notarize    notarize + staple (needs KEYCHAIN_PROFILE or APPLE_ID/APPLE_PASSWORD/APPLE_TEAM_ID)"
	@echo "  make release     build + package + notarize (set IDENTITY to a Developer ID to be distributable)"
	@echo "  make version     bump patch (e.g. make version VERSION=1.1.0 to set explicitly; show to print)"
	@echo "  make clean       remove build/ and dist/"
	@echo ""
	@echo "Signing: ad-hoc by default. For public distribution pass a Developer ID:"
	@echo "  make build IDENTITY='Developer ID Application: Name (TEAMID)'"
	@echo "Notarization credentials (one of):"
	@echo "  KEYCHAIN_PROFILE=WindowsV   — stored via 'xcrun notarytool store-credentials'"
	@echo "  APPLE_ID=... APPLE_PASSWORD=... APPLE_TEAM_ID=..."

icon:
	./icon/generate_icon.sh

build:
	./scripts/build.sh

package zip dmg: build
	./scripts/package.sh

notarize:
	./scripts/notarize.sh

release: package
	./scripts/notarize.sh

version:
	./scripts/version.sh $(if $(VERSION),set $(VERSION),patch)

clean:
	rm -rf build dist

sign:
	./scripts/build.sh
