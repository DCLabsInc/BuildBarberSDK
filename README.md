# BuildBarber SDK

BuildBarberSDK lets an iOS app collect a screen recording, checklist status, and
user feedback for a test session so it will all appear in the BuildBarber portal.

## Requirements

- iOS 27.0 or later
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

        BuildBarberSessionManager.shared.configure(
            apiKey: "YOUR_CLIENT_API_KEY",
            testType: .feature,
            codeword: "YOUR_CODEWORD",
            checklistItems: [
                "Sign in",
                "Add a dog walk",
                "Review walk history"
            ]
        )
    }

    func startFeedbackSession() {
        BuildBarberSessionManager.shared.startSession(presentingFrom: self)
    }
}
```

Call `startFeedbackSession()` from an app control such as a “Send feedback”
button. The SDK asks the user to confirm, then presents Apple's content-sharing
picker; recording begins only after the user selects what to share. The SDK
records screen and audio, and displays a floating button for opening the session
menu.

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

The portal accepts videos up to 100 MB. The SDK records at a fixed bitrate and
automatically stops recording after about 5 minutes 20 seconds, showing an
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
