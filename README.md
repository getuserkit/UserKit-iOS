<h1 align="center">UserKit</h1>

<h3 style="font-size:26" align="center">Talk to your users, right inside your app.</h3>

<p align="center">
  <a href="https://docs.superwall.com/docs/installation-via-spm">
    <img src="https://img.shields.io/badge/SwiftPM-Compatible-orange" alt="SwiftPM Compatible">
  </a>
  <a href="https://getuserkit.com/">
    <img src="https://img.shields.io/badge/iOS-15.0+-blue" alt="iOS 15.0+">
  </a>
  <a href="https://github.com/getuserkit/UserKit-iOS/blob/master/LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-green/" alt="MIT License">
  </a>
  <a href="https://getuserkit.com/">
    <img src="https://img.shields.io/github/v/tag/getuserkit/UserKit-ios" alt="Version Number">
  </a>
</p>

---

Start a call, view their screen, see where they tap, and solve problems instantly inside your own app all with 3 lines of code.

## Demo

<p align="center">
  <img src="demo.gif" alt="UserKit Demo">
</p>

## Features

|     | UserKit                                                                                                  |
| --- | -------------------------------------------------------------------------------------------------------- |
| 🖼️  | UserKit runs entirely inside a native Picture in Picture window, keeping your app’s interface untouched. |
| 🖥️  | Watch how users actually use your app. See their screen and touches, live and in context.                |
| 👍  | No permissions request request required                                                                  |
| 📞  | Full CallKit integration built in.                                                                       |
| 📝  | [Online documentation](https://docs.getuserkit.com) up to date                                           |
| 💯  | Well maintained - [frequent releases](https://github.com/getuserkit/UserKit-iOS/releases)                |
| 📮  | Great support - email a founder: pete@getuserkit.com                                                     |

## 📦 Installation

### Swift Package Manager

The preferred installation method is with [Swift Package Manager](https://swift.org/package-manager/). This is a tool for automating the distribution of Swift code and is integrated into the swift compiler. In Xcode, do the following:

- Select **File ▸ Add Packages...**
- Search for `https://github.com/getuserkit/userkit-ios` in the search bar.
- Set the **Dependency Rule** to **Up to Next Major Version** with the lower bound set to **1.1.0**.
- Make sure your project name is selected in **Add to Project**.
- Then, **Add Package**.

## 🚀 Getting Started

```swift
import UserKit

// Initialize with your API key
UserKit.configure(apiKey: "your_api_key")

// Identify your app user
UserKit.shared.identify(id: "1", name: "Example User", email: "example@user.com")
```

That's all that is required!

Now you can jump over to [getuserkit.com](https://getuserkit.com), find your identified user and give them a call.

## 🤝 Contributing

Please see the [CONTRIBUTING](.github/CONTRIBUTING.md) file for how to help.
