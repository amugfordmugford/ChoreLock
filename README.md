Here is a professional and ready-to-use `README.md` file for your project. It summarizes the features, tech stack, and setup instructions based on the code you’ve written.

You can create this file directly in Xcode:

1.  **File** \> **New** \> **File...**
2.  Scroll down to the **Other** section and select **Markdown File**.
3.  Name it `README.md`.
4.  Paste the content below into it.

-----

# ChoreLock

**ChoreLock** is a macOS application designed to help parents manage screen time and enforce chore completion. The app "locks" the computer screen during specific hours, requiring the user (child) to complete a checklist of daily tasks before the device unlocks for recreational use.

## 🚀 Features

  * **Gatekeeper Mode:** Automatically locks the screen during configured "Chore Hours" (default: 1 PM - 3 PM).
  * **Immersive Lock Screen:** Hides the Dock, Menu Bar, and other windows to remove distractions until tasks are done.
  * **Multi-User Support:** switching between profiles (e.g., Micah, Aidan) with independent task tracking.
  * **Smart Templates:** Automatically switches between **Weekday** and **Weekend** task lists based on the current date.
  * **Parent Admin Mode:**
      * Protected by a PIN (Default: `1234`).
      * Add, remove, or edit tasks dynamically.
      * Manually unlock the device if needed.
  * **Persistence:** Remembers completed tasks for the day so the screen doesn't re-lock if the computer sleeps/wakes.

## 🛠 Tech Stack

  * **Language:** Swift 5
  * **UI Framework:** SwiftUI
  * **Window Management:** AppKit (NSWindow, NSApplication) for controlling window levels and hiding system UI.
  * **Architecture:** MVVM (Model-View-ViewModel) using `ObservableObject` for state management.

## ⚙️ Configuration

The app uses `GatekeeperLogic.shared` to handle configuration. You can modify these settings in `GatekeeperLogic.swift`:

**Change Chore Hours:**

```swift
// GatekeeperLogic.swift
let startHour = 13 // 1:00 PM
let endHour = 15   // 3:00 PM
```

**Change Admin PIN:**

```swift
// ContentView.swift
let parentPin = "1234"
```

## 📦 Installation & Setup

1.  Clone the repository:
    ```bash
    git clone https://github.com/amugfordmugford/ChoreLock.git
    ```
2.  Open the project in **Xcode**.
3.  Build and Run (`Cmd + R`).
      * *Note:* Upon first launch, ensure you allow any requested permissions. The app modifies window levels to stay on top of other applications.

## 📱 Usage

### For the Parent (Admin)

1.  If the screen is locked, enter the PIN (`1234`) in the footer and click **Admin**.
2.  Select a Child's profile.
3.  Select **Weekday** or **Weekend** to edit the template for that specific day type.
4.  Add or delete tasks as necessary.
5.  Click **Done** to save and return to the lock screen.

### For the Child

1.  Launch the app (or wake the computer during chore hours).
2.  Your customized task list will appear.
3.  Check off items as you complete them (e.g., "Brush Teeth", "Feed Cats").
4.  Once all items are checked, the screen will unlock automatically\!

## 🛡 Disclaimer

This app is intended for family use to encourage habits. It is not a root-level security device; it uses standard macOS window layering to cover the screen.

-----

### Future Roadmap

  * [ ] Allow editing chore hours from the Admin UI (instead of code).
  * [ ] Add cloud sync so parents can check status from their phones.
  * [ ] Gamification/Reward points system.
