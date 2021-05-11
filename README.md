# **LocalConsole**

Welcome to LocalConsole! This Swift Package makes on-device debugging easy with a convenient PiP-style console that can display items in the same way ```print()``` will in Xcode. This tool can also dynamically display view frames and restart SpringBoard right from your live app.

<img src="https://github.com/duraidabdul/LocalConsole/blob/main/Demo.gif?raw=true" width="250" height="500">

## **Setup**

1. In your Xcode project, navigate to File > Swift Packages > Add Package Dependancy...

2. Paste the following into the URL field: https://github.com/duraidabdul/LocalConsole/

3. Once the package dependancy has been added, import LocalConsole and create an easily accessible global instance of ```Console.shared```.
```swift
import LocalConsole

let localConsole = Console.shared
```

## **Usage**
Once prepared, the localConsole can be used throughout your project.
```swift

// Show local console.
localConsole.isVisible = true

// Hide local console.
localConsole.isVisible = false

// Print items to local console.
localConsole.print("Hello, world!")

// Clear local console text.
localConsole.clear()
```
