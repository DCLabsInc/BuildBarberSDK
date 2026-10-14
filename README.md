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
secret), and set `apiEndpoint` to the session-upload endpoint for your service.

```swift
import BuildBarberSDK
import UIKit

final class FeedbackViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        SaaSSessionManager.shared.configure(
            apiKey: "YOUR_CLIENT_API_KEY",
            apiEndpoint: URL(string: "https://api.example.com/sessions")!,
            checklistItems: [
                "Open the account screen",
                "Update the profile"
            ]
        )
    }

    func startFeedbackSession() {
        SaaSSessionManager.shared.startSession(presentingFrom: self)
    }
}
```

Call `startFeedbackSession()` from an app control such as a “Send feedback”
button. The SDK asks the user to confirm, then presents Apple's content-sharing
picker; recording begins only after the user selects what to share. The SDK
records screen and audio, and displays a floating button for opening the session
menu.

Checklist entries are provided in order when configuring. Update an entry by
its zero-based index, for example when the corresponding app action completes:

```swift
SaaSSessionManager.shared.updateChecklist(itemIndex: 0, isTicked: true)
```

When the user ends the session, the SDK sends the checklist, feedback, session
metadata, and (when available) the recording to `apiEndpoint` as a
`multipart/form-data` POST. The `payload` part contains JSON; the optional
`video` part is an MP4 recording. If the app is backgrounded during recording,
the SDK pauses the session and prompts the user to provide feedback when they
return.
