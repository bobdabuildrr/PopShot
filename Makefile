APP_NAME    := PopShot
BUNDLE_ID   := app.popshot.PopShot
VERSION     ?= $(shell cat VERSION)
BUILD_DIR   := build
APP         := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR ?= /Applications

.PHONY: all app build install uninstall run zip test icon set-repo clean

all: app

# `make app UNIVERSAL=1` builds an arm64 + x86_64 binary (used for releases).
build:
ifeq ($(UNIVERSAL),1)
	swift build -c release --arch arm64
	swift build -c release --arch x86_64
	mkdir -p $(BUILD_DIR)
	lipo -create -output $(BUILD_DIR)/$(APP_NAME)-bin \
		"$$(swift build -c release --arch arm64 --show-bin-path)/$(APP_NAME)" \
		"$$(swift build -c release --arch x86_64 --show-bin-path)/$(APP_NAME)"
else
	swift build -c release
	mkdir -p $(BUILD_DIR)
	cp "$$(swift build -c release --show-bin-path)/$(APP_NAME)" $(BUILD_DIR)/$(APP_NAME)-bin
endif

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp $(BUILD_DIR)/$(APP_NAME)-bin "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(APP)/Contents/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" "$(APP)/Contents/Info.plist"
	codesign --force --sign - --timestamp=none "$(APP)"
	@echo "Built $(APP) ($(VERSION))"

install: app
	@./scripts/quit-running.sh
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	ditto "$(APP)" "$(INSTALL_DIR)/$(APP_NAME).app"
	rm -rf "$(APP)"  # one copy only, so Spotlight doesn't list a second PopShot
	open "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app — look for the viewfinder icon in your menu bar."

uninstall:
	@./scripts/uninstall.sh
	rm -rf "$(APP)"

# Runs the freshly built app in the foreground with logs in the terminal (Ctrl-C quits cleanly).
run: app
	@./scripts/quit-running.sh
	POPSHOT_DEBUG=1 "$(APP)/Contents/MacOS/$(APP_NAME)"

zip: app
	cd $(BUILD_DIR) && rm -f $(APP_NAME).zip && ditto -c -k --keepParent $(APP_NAME).app $(APP_NAME).zip
	@shasum -a 256 $(BUILD_DIR)/$(APP_NAME).zip

# Headless check of detection, the editor (rendering, canvas input, crop, blur) and OCR.
test: app
	"$(APP)/Contents/MacOS/$(APP_NAME)" --self-test Tests/Fixtures/sample-screenshot.png $(BUILD_DIR)/selftest.png

icon:
	./scripts/make-icon.sh

# `make set-repo GH_USER=yourname` points the README, installer and app at your GitHub repo.
set-repo:
	@test -n "$(GH_USER)" || (echo "usage: make set-repo GH_USER=<your-github-username>" && exit 1)
	@grep -rl "YOUR_GITHUB_USER" README.md scripts docs packaging Sources | xargs sed -i '' "s/YOUR_GITHUB_USER/$(GH_USER)/g"
	@echo "Repo set to github.com/$(GH_USER)/PopShot"

clean:
	rm -rf .build $(BUILD_DIR)
