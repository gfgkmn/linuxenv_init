# XCUITest screenshot tour — template

`simctl io tap` is ignored by current iOS runtimes, so a multi-screen tour
needs a real UI-test target. This is a template to adapt, not something this
skill installs: the target belongs to the project under test, and the steps
below name that project's own screens.

Adapt the identifiers, keep the shape.

## 1. Add the target

XcodeGen (`project.yml`):

```yaml
  AppUITests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - Tests/AppUITests
    dependencies:
      - target: App
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        PRODUCT_BUNDLE_IDENTIFIER: com.example.app.uitests
        TEST_TARGET_NAME: App
```

Then `xcodegen generate`. Plain Xcode projects: File ▸ New ▸ Target ▸ UI
Testing Bundle.

## 2. The tour

```swift
import XCTest

final class ScreenshotTour: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways      // without this it is discarded on pass
        add(a)
    }

    func testTour() {
        let app = XCUIApplication()
        // A launch argument lets the app seed demo data and skip onboarding,
        // so the tour starts from the state actually worth reviewing.
        app.launchArguments += ["-uiTestSeed"]
        app.launch()

        shot(app, "01-launch")

        // Address elements by accessibility identifier, never by coordinates:
        // identifiers survive layout changes, coordinates do not.
        app.buttons["startButton"].tap()
        XCTAssertTrue(app.staticTexts["todayTitle"].waitForExistence(timeout: 5))
        shot(app, "02-today")

        app.tabBars.buttons["Reports"].tap()
        shot(app, "03-reports")
    }
}
```

Assert that the next screen appeared before capturing. Without the assertion a
mid-transition frame gets captured and the gallery shows a half-drawn screen.

## 3. Run and extract

```bash
xcodebuild test \
  -project X.xcodeproj -scheme S \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/tour.xcresult

xcrun xcresulttool export attachments \
  --path /tmp/tour.xcresult --output-path ~/Temp/cc-shots/tour
```

Then build a manifest from `~/Temp/cc-shots/tour` and hand it to
`cc-gallery.py`.

## Notes

- The tour writes into the simulator. `xcrun simctl erase <UDID>` resets it.
- Keep the tour to screens whose look is actually in question. A tour that
  captures everything costs review attention rather than saving it.
- If the app has no accessibility identifiers yet, adding them is the real
  prerequisite — and they improve VoiceOver support at the same time.
