# Same layout as yachtvaa/native: project.yml is the source, the generated
# TagRecorder.xcodeproj is committed so Xcode Cloud builds it without XcodeGen.

DERIVED  := /tmp/tagvaa-derived
DEST     := platform=macOS,variant=Mac Catalyst
UNSIGNED := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

.PHONY: project test build check-project

## Regenerate the Xcode project after adding or moving a source file; commit it.
project:
	xcodegen generate

## Recording logic (no Tag, phone or simulator needed).
test:
	cd RecorderCore && swift test

## Compile the app here without the iOS platform: unsigned Mac Catalyst build,
## in its own derived data so it never replaces the app Xcode runs.
build: check-project
	xcodebuild -project TagRecorder.xcodeproj -scheme TagRecorder -destination '$(DEST)' \
		-derivedDataPath $(DERIVED) $(UNSIGNED) build -quiet

## Does the committed project still match project.yml?
check-project:
	@xcodegen generate >/dev/null
	@if ! git diff --quiet -- TagRecorder.xcodeproj || \
	    [ -n "$$(git ls-files --others --exclude-standard -- TagRecorder.xcodeproj)" ]; then \
		echo "the committed TagRecorder.xcodeproj does not match project.yml -- commit the regenerated one"; \
		exit 1; \
	else echo "project ok (committed, and matches project.yml)"; fi
