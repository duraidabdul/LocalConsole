# **LocalConsole**

Welcome to LocalConsole! This Swift Package makes on-device debugging easy with a convenient PiP-style console that can display items in the same way ```print()``` will in Xcode. This tool can also dynamically display view frames and restart SpringBoard right from your live app.

<img src="https://github.com/duraidabdul/LocalConsole/blob/main/Demo.gif?raw=true" width="240">

## **Setup**

1. In your Xcode project, navigate to File > Swift Packages > Add Package Dependancy...

2. Paste the following into the URL field: https://github.com/duraidabdul/LocalConsole/

3. Once the package dependancy has been added, import LocalConsole and create an easily accessible global instance of ```Console.shared```.
```swift
import LocalConsole

let localConsoleManager = LCManager.shared
```

## **Usage**
Once prepared, the localConsole can be used throughout your project.
```swift

// Show the console view.
localConsoleManager.isVisible = true

// Hide the console view.
localConsoleManager.isVisible = false
```

```swift
// Print items to the console view.
localConsoleManager.print("Hello, world!")

// Clear text in the console view.
localConsoleManager.clear()

// Copy the console view text to the device's clipboard.
localConsoleManager.copy()
```

```swift
// Change the console view font size.
localConsoleManager.fontSize = 5
```


## **To-Do**
* Custom console view size
* Support for iOS 13
* Screen edge console hiding
* Custom pinch to resize gesture
* Make console view reactive to landscape/portrait switch
