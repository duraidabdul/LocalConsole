# **LocalConsole**

## **Usage**

1. In your Xcode project, go to File > Swift Packages > Add Package Dependancy...

2. Paste the following into the URL field: https://github.com/duraidabdul/LocalConsole/

Once the package dependancy has been added, import LocalConsole to begin using it.
```swift
import LocalConsole
```


```swift

// Show console.
Console.shared.isVisible = true

// Print to console.
Console.shared.print("Hello, world!")

// Clear console.
Console.shared.clear()
```

## **Global Usage**
To reuse this code throughout your project without the need to print it, you can create a Swift file as follows.
```swift
import LocalConsole

func printLocal(_ items: Any) {
    Console.shared.print(items)
}

func clearLocal() {
    Console.shared.clear()
}

var localConsoleVisible = false {
    didSet {
        Console.shared.isVisible = consoleVisible
    }
}
```
