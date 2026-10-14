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
secret), and provide the test type and codeword supplied by BuildBarber.
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
            codeword: "YOUR_CODEWORD"
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

## How checklist tick boxes are pulled from the API

When a session starts, the SDK fetches the configured test from BuildBarber:

- `GET https://portal.buildbarber.com/api/sdk/v1/tests?testType=<type>&codeword=<codeword>`
- Header: `X-Api-Key: <your key>`

From the response, the SDK renders:

- `title`, `description`, and `instructions`
- each entry in `checklist` as a tick box
  - `key` = stable identifier used when submitting results
  - `label` = text shown next to the tick box
  - `kind` = source type (`task` for feature tests, `feature` for release tests)

The SDK submits checked items using checklist **keys** (not labels).

## Auto-tick checklist items from app events

You can mark checklist items as completed from your app when a known action
happens. Use the item index from the fetched checklist.

```swift
// Example: auto-tick the first checklist item when the user completes Dog walks
BuildBarberSessionManager.shared.updateChecklist(itemIndex: 0, isTicked: true)
```

This lets your app reflect completed tasks/features automatically while still
allowing testers to review and submit from the SDK UI.

## Submission behavior

The SDK follows the test definition returned by BuildBarber:

- If `showPassFailButtons == true`, the user sees **Pass** and **Fail**.
- If `showPassFailButtons == false`, the user sees **Submit feedback** only.

Validation is enforced before submission:

- Pass requires all checklist items to be ticked.
- Fail requires feedback text.
- Feedback-only submissions omit `outcome`.

On submit, the SDK posts results to:

- `POST https://portal.buildbarber.com/api/sdk/v1/tests/results`

Payload includes test type, codeword, tester email, optional outcome,
optional feedback, and checked checklist keys.

## Error handling

If the test fetch fails, the SDK shows an error state to the tester.
A `404 test_not_found` typically means the codeword is wrong for the selected
`testType` or API key scope.

Never log or expose your API key in client-side diagnostics.
