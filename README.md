# BuildBarberSDK

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

## Submission behavior

The session menu shows **Pass** and **Fail** buttons. Validation is enforced before submission:

- Pass requires all checklist items to be ticked.
- Fail requires feedback text.
- Feedback-only submissions omit `outcome`.

On submit, the SDK posts results to:

- `POST https://portal.buildbarber.com/api/sdk/v1/tests/results`

Payload includes test type, codeword, tester email, optional outcome,
optional feedback, and checked checklist keys.

Never log or expose your API key in client-side diagnostics.
