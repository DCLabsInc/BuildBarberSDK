# BuildBarberSDK

BuildBarberSDK lets an iOS app collect session feedback with a screen and audio recording, a checklist, and a feedback form.

## Requirements

- iOS 27.0 or later
- Xcode with Swift Package Manager support

## Add the package

In Xcode, choose **File > Add Package Dependencies…** and enter:

```text
https://github.com/DCLabsInc/BuildBarberSDK
```

Select the `BuildBarberSDK` package product for your app target.

## Configure and start a session

Import the package, configure the shared manager with your API key, upload endpoint, and checklist, then start a session from a view controller:

```swift
import BuildBarberSDK
import UIKit

final class FeedbackViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        SaaSSessionManager.shared.configure(
            apiKey: "YOUR_API_KEY",
            apiEndpoint: URL(string: "https://your-service.example/sessions")!,
            checklistItems: ["Complete onboarding", "Find a product"]
        )
    }

    @IBAction private func startFeedbackSession(_ sender: Any) {
        SaaSSessionManager.shared.startSession(presentingFrom: self)
    }
}
```

Replace the example API key and URL with the values for your service. Treat credentials appropriately for a client application; values embedded in an app can be extracted.

When `startSession` is called, the SDK asks the user to confirm recording and uses the system sharing picker to select what to capture. A floating control opens the session menu, where the user can review the checklist and enter feedback, continue recording, or end the session to upload. Recording can also be interrupted when the app enters the background; the SDK pauses capture and prompts the user to finish providing feedback when they return.

You can update checklist state by its zero-based index:

```swift
SaaSSessionManager.shared.updateChecklist(itemIndex: 0, isTicked: true)
```

## Upload endpoint

When a session ends, the SDK sends a `POST` request to `apiEndpoint` as `multipart/form-data`. The request includes a JSON `payload` part and, when a recording is available, a `video` part containing an MP4 file. Configure an endpoint that accepts this request format.
