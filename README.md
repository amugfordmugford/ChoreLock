# ChoreLock 🔒

**ChoreLock** is a macOS application designed to help parents manage screen time and enforce chore completion. The app "locks" the computer screen during specific hours, requiring the user (child) to complete a checklist of daily tasks before the device unlocks for recreational use.

## 🚀 Features

* **Gatekeeper Mode:** Automatically activates a full-screen shield between specific hours (Current Config: **6:00 AM - 9:00 AM**).
* **Menu Bar Access:** A discrete "Shield" icon 🛡️ in the menu bar allows parents to access settings even when the app is hidden or outside active hours.
* **Smart Templates:** Automatically switches between **Weekday** and **Weekend** task lists based on the current date.
* **Device Assignment:** Persistently assigns the Mac to a specific child (e.g., Micah or Aidan), remembering their specific progress.
* **Parent Admin Mode:**
    * Protected by a PIN (Default: `8585`).
    * Add, remove, or edit tasks dynamically.
    * View completion logs for the last 14 days.
    * Toggle "Launch at Login" capability.
* **Immersive Lock:** Hides the Dock, Menu Bar, and prevents quitting to remove distractions until tasks are done.

## 🛠 Tech Stack

* **Language:** Swift 5
* **UI Framework:** SwiftUI
* **Window Management:** AppKit (NSWindow, NSApplication) for controlling window levels and hiding system UI.
* **Background Tasks:** `ServiceManagement` for Launch at Login support.
* **Architecture:** Singleton Logic Controller (`GatekeeperLogic`) with Observable state.

## ⚙️ Configuration

Since this is a prototype, some core settings are configured in the source code (`ChoreLockApp.swift`).

### 1. Change Active Hours
Look for `GatekeeperLogic` class to change the lock window:
```swift
// GatekeeperLogic class
let startHour: Int = 06  // 6 AM
let endHour: Int = 09    // 9 AM
```

### 2. Change Admin PIN
Look for `ContentView` to change the parent code:
```swift
// ContentView struct
let parentPin = "8585"
```

## 📦 Installation & Setup

1.  Clone the repository:
    ```bash
    git clone [https://github.com/amugfordmugford/ChoreLock.git](https://github.com/amugfordmugford/ChoreLock.git)
    ```
2.  Open the folder in **Xcode**.
3.  **Build and Run** (`Cmd + R`).
    * *Note:* Upon first launch, allow any requested permissions. The app modifies window levels to stay on top of other applications.

## 📱 Usage

### For the Parent (Admin)

**When Locked:**
1.  Enter the PIN (`8585`) in the bottom footer.
2.  Click **Admin** to open the settings panel.

**When Unlocked/Hidden:**
1.  Look for the **Shield Icon (🛡️)** in the macOS Menu Bar (top right near the clock).
2.  Click it and select **"Admin Settings..."**.
3.  Enter the PIN to access the dashboard.

**In the Dashboard:**
* **Select a Child:** Choose whose profile is active on this computer.
* **Edit Tasks:** Add or delete tasks. Use the toggle to switch between editing Weekday vs Weekend lists.
* **Reset:** Use the orange button to reset today's checklist from the saved template.

### For the Child

1.  Wake the computer during chore hours (e.g., 7:00 AM).
2.  The screen will be locked with your specific task list.
3.  Check off items as you complete them (e.g., "Brush Teeth", "Feed Cats").
4.  Once all items are checked, you will see a success message and the screen will unlock automatically!

## 🛡 Disclaimer

This app is intended for family use to encourage habits. It is not a kernel-level security device; it uses standard macOS window layering to cover the screen. Smart kids might find a way around it—congratulate them on their engineering skills if they do!
