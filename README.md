# **LocalConsole**

## **Setup**

1. In your Xcode project, navigate to File > Swift Packages > Add Package Dependancy...

2. Paste the following into the URL field: https://github.com/duraidabdul/LocalConsole/

Once the package dependancy has been added, import LocalConsole and create an easily accessible global instance of ```Console.shared```.
```swift
import LocalConsole

let localConsole = Console.shared
```

## **Usage**
After preparing the localConsole, it can be conveniently used throughout a project.
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
