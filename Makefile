PROJECT := Livepaper.xcodeproj
DESTINATION := platform=macOS,arch=arm64
DERIVED_DATA := build/DerivedData
XCODEBUILD := xcodebuild -project $(PROJECT) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) -quiet

.PHONY: all gen build test lint strings ffmpeg shader-tools notices release-dry-run clean

all: gen lint test build

gen:
	xcodegen generate

build: gen
	$(XCODEBUILD) -scheme Livepaper build
	$(XCODEBUILD) -scheme Gallery build
	$(XCODEBUILD) -scheme livepaper-cli build
	[ ! -d Tools/soak ] || swift build --package-path Tools/soak --quiet

test:
	swift test --package-path Packages/LivepaperKit
	swift test --package-path Packages/DesignSystem
	swift test --package-path Tools/release

lint:
	swiftlint lint --strict --quiet

# Brings the design system's string catalog up to date with the strings the
# last Xcode build found in its sources.
strings: build
	xcrun xcstringstool sync Packages/DesignSystem/Sources/DesignSystem/Resources/Localizable.xcstrings \
		--stringsdata $$(find $(DERIVED_DATA) -name '*.stringsdata' -path '*DesignSystem-t.build*')

ffmpeg:
	Helpers/ffmpeg/build.sh

shader-tools:
	Helpers/shader-tools/build.sh

# The notices, from what ships: into Resources/Credits.rtf and the README.
notices:
	swift run --package-path Tools/release --quiet release-kit notices --root . --write

# Every release step but publishing, ad-hoc signed, into build/release/.
release-dry-run:
	Tools/release/release.sh --dry-run

clean:
	rm -rf build $(PROJECT) Packages/*/.build Tools/soak/.build Tools/release/.build
