# BuildBarber SDK

BuildBarberSDK lets an iOS app collect a screen recording, checklist status, and
user feedback for a test session so it will all appear in the BuildBarber portal.

## Requirements

- iOS 18.0 or later
- Xcode with Swift Package Manager support

## Add the package

In Xcode, choose **File > Add Package Dependencies…** and enter:

```text
https://github.com/DCLabsInc/BuildBarberSDK
```

Select the `BuildBarberSDK` library for your app target.

> [!IMPORTANT]
> **Sign in with Apple is required.** Enable the **Sign in with Apple**
> capability on your app target in Xcode (and its App ID). Swift Package Manager
> libraries cannot add this entitlement for you.

> [!IMPORTANT]
> **Camera roll access is required to save the recording.** Add
> `NSPhotoLibraryAddUsageDescription` to your app's Info.plist (for example,
> "Save your feedback session recording to Photos"). The SDK asks for add-only
> Photos permission and saves the video to the camera roll after a successful
> submission.

Other Info.plist privacy keys depend on which features you enable:

| Key | When it is required |
| --- | --- |
| `NSPhotoLibraryAddUsageDescription` | Required if saving the captured video to Photos. |
| `NSMicrophoneUsageDescription` | Only if microphone recording is enabled (the SDK currently does not record the microphone). |
| `NSCameraUsageDescription` | Only if camera preview/capture is enabled (the SDK currently does not use the camera). |

> [!NOTE]
> Call `startSession(presentingFrom:)` on the main thread. If called from an early
> lifecycle hook such as SwiftUI `onAppear`, the SDK waits briefly (about 2.5
> seconds at most) for a foreground-active scene and a presenter attached to a
> window before presenting.

## Configure and start a session

Configure the shared session manager before offering the session flow to users.
Use an API key appropriate for a client app (never embed a privileged server
secret), and provide the test type and codeword supplied by BuildBarber,
along with the checklist items to show testers.
The test type is `.feature` or `.release`.

```swift
import BuildBarberSDK
import UIKit

final class FeedbackViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        guard let apiKey = BuildBarberAppConfiguration.apiKey() else {
            assertionFailure("Missing SDKAPIKey in Info.plist; see Config.template.xcconfig")
            return
        }

        BuildBarberSessionManager.shared.configure(
            apiKey: apiKey,
            testType: .feature,
            codeword: "YOUR_CODEWORD",
            checklistItems: [
                "Sign in",
                "Add a dog walk",
                "Review walk history"
            ]
        )

        BuildBarberSessionManager.shared.startSession(presentingFrom: self)
    }
}
```

After a crash, the SDK searches up to three directory levels in the app bundle,
Documents, and (optionally) an App Group container for `.dSYM` bundles. If any
are present, it uploads them with `crash.log` in one ZIP; otherwise it uploads
the plain crash log. Configure `dsymAppGroupIdentifier` when your app places
symbols in an App Group. Installed apps cannot access Xcode DerivedData.
SwiftPM compiles this SDK into the host app, so its code is normally covered by
the app executable's dSYM rather than a separate `BuildBarberSDK.dSYM`. A dSYM
is not normally shipped inside an installed app; the host app must explicitly
make any dSYM available in one of the searched locations at runtime.

### Keeping the API key out of source control

1. Copy `Config.template.xcconfig` to `Config.xcconfig` (git-ignored) in your
   app's project root and set `SDK_API_KEY = your_actual_key_here`.
2. Assign `Config.xcconfig` to your target's build configurations
   (Project > Info > Configurations).
3. Add `SDKAPIKey` = `$(SDK_API_KEY)` to your app's Info.plist.
4. Add `Config.xcconfig` to `.gitignore`. Commit only the template, and have
   teammates copy it.

Add this to the first view controller your app opens, so the session starts from
`viewDidLoad`. The SDK asks the user to confirm, then starts recording the app's screen
and audio with ReplayKit. It also displays a floating button for opening the
session menu.

## Checklist items

Checklist items are provided statically through the `checklistItems` argument of
`BuildBarberSessionManager.shared.configure(...)`. They are **not** pulled
dynamically from the BuildBarber API. Each item is shown to the tester as a tick
box, and the item text is submitted as the checked item identifier.

To tick an item automatically when the corresponding action completes in your
app, call `tickChecklistItem(at:)` on the shared session manager. The index is
zero-based and matches the item's position in the `checklistItems` array passed
to `configure`:

```swift
// checklistItems: ["Sign in", "Add a dog walk", "Review walk history"]
func didAddDogWalk() {
    BuildBarberSessionManager.shared.tickChecklistItem(at: 1)
}
```

Call this while a session is active. Invalid indices and calls outside an active
session are ignored. The tester can still manually untick an automatically
checked item in the session menu.

## Recording limits

The portal accepts videos up to 100 MB. The SDK records at a fixed 1 Mbps bitrate (downscaled to at most 1280 px on the long side) and
automatically stops recording after about 10 minutes 40 seconds, showing an
alert and then the session menu. If a finished recording is still over 100 MB,
the video is not uploaded; the feedback is still submitted, the video is saved
to Photos, and the tester is told to upload it manually from their library.

## Submission behavior

The session menu shows **Pass** and **Fail** buttons. Validation is enforced before submission:

- Pass requires all checklist items to be ticked.
- Fail requires feedback text.
- Feedback-only submissions omit `outcome`.
- Testers can sign in with Apple to fill in their email address.

Apps using the Apple sign-in button must enable the **Sign in with Apple**
capability for their app target in Xcode. Swift Package Manager libraries cannot
add this app entitlement. Apple may only provide the tester's email on the first
authorization. If authorization fails with error 1000, verify that the capability
is enabled for the host app's target and its App ID.

On submit, the SDK will post results to:

- `POST https://portal.buildbarber.com/api/sdk/v1/tests/results`

Payload (JSON) includes test type, codeword, tester email, optional outcome,
optional feedback, and checked checklist keys. The response contains a
`testRecordId`. The session recording, when available, is then uploaded as
`multipart/form-data` in a field named `video` to:

- `POST https://portal.buildbarber.com/api/sdk/v1/tests/{testRecordId}/video`

If submission or the video upload fails, the SDK shows an alert with the full
error text and a **Copy to clipboard** button. Note that a failed video upload
happens after the result was recorded.

Never log or expose your API key in client-side diagnostics.
