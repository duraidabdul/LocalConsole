//
//  LocalConsole.swift
//
//  Created by Duraid Abdul.
//  Copyright © 2021 Duraid Abdul. All rights reserved.
//

//#if canImport(UIKit)

import UIKit
import SwiftUI

var GLOBAL_BORDER_TRACKERS: [BorderManager] = []

@available(iOSApplicationExtension, unavailable)
public class LCManager: NSObject, UIGestureRecognizerDelegate {
    
    public static let shared = LCManager()
    
    /// Set the font size. The font can be set to a minimum value of 5.0 and a maximum value of 20.0. The default value is 7.5.
    public var fontSize: CGFloat = 7.5 {
        didSet {
            guard fontSize >= 4 else { fontSize = 4; return }
            guard fontSize <= 20 else { fontSize = 20; return }
            
            setAttributedText(consoleTextView.text)
        }
    }
    
    var isConsoleConfigured = false
    
    /// A high performance text tracker that only updates the view's text if the view is visible. This allows the app to run print to the console with virtually no performance implications when the console isn't visible.
    var currentText: String = "" {
        didSet {
            if isVisible {
                
                // Ensure we are performing UI updates on the main thread.
                DispatchQueue.main.async {
                    
                    // Ensure the console doesn't get caught into any external animation blocks.
                    UIView.performWithoutAnimation {
                        self.commitTextChanges(requestMenuUpdate: oldValue == "" || (oldValue != "" && self.currentText == ""))
                    }
                }
            }
        }
    }
    
    let defaultConsoleSize = CGSize(width: 228, height: 142)
    
    /// The fixed size of the console view.
    lazy var consoleSize = defaultConsoleSize {
        didSet {
            consoleView.frame.size = consoleSize
            
            // Update text view width.
            if consoleView.frame.size.width > ResizeController.kMaxConsoleWidth {
                consoleTextView.frame.size.width = ResizeController.kMaxConsoleWidth - 4
            } else if consoleView.frame.size.width < ResizeController.kMinConsoleWidth {
                consoleTextView.frame.size.width = ResizeController.kMinConsoleWidth - 4
            } else {
                consoleTextView.frame.size.width = consoleSize.width - 4
            }
            
            // Update text view height.
            if consoleView.frame.size.height > ResizeController.kMaxConsoleHeight {
                consoleTextView.frame.size.height = ResizeController.kMaxConsoleHeight - 4
                + (consoleView.frame.size.height - ResizeController.kMaxConsoleHeight) * 2 / 3
            } else if consoleView.frame.size.height < ResizeController.kMinConsoleHeight {
                consoleTextView.frame.size.height = ResizeController.kMinConsoleHeight - 4
                + (consoleView.frame.size.height - ResizeController.kMinConsoleHeight) * 2 / 3
            } else {
                consoleTextView.frame.size.height = consoleSize.height - 4
            }
            
            consoleTextView.contentOffset.y = consoleTextView.contentSize.height - consoleTextView.bounds.size.height
            
            // TODO: Snap to nearest position.
            
            UserDefaults.standard.set(consoleSize.width, forKey: "LocalConsole_Width")
            UserDefaults.standard.set(consoleSize.height, forKey: "LocalConsole_Height")
        }
    }
    
    /// Strong reference keeps the window alive.
    var consoleWindow: ConsoleWindow?
    
    // The console needs a parent view controller in order to display context menus.
    let viewController = UIViewController()
    lazy var consoleView = viewController.view!
    
    /// Text view that displays printed items.
    let consoleTextView = InvertedTextView()
    
    /// Button that reveals menu.
    lazy var menuButton = UIButton()
    
    /// Tracks whether the PiP console is in text view scroll mode or pan mode.
    var scrollLocked = true
    
    /// Feedback generator for the long press action.
    let feedbackGenerator = UISelectionFeedbackGenerator()
    
    lazy var panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(consolePiPPanner(recognizer:)))
    lazy var longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressAction(recognizer:)))
    
    /// Gesture endpoints. Each point represents a corner of the screen. TODO: Handle screen rotation.
    var possibleEndpoints: [CGPoint] {
        if consoleSize.width < UIScreen.portraitSize.width - 112 {
            return [CGPoint(x: consoleSize.width / 2 + 12,
                            y: (UIScreen.hasRoundedCorners ? 44 : 16) + consoleSize.height / 2 + 12),
                    CGPoint(x: UIScreen.portraitSize.width - consoleSize.width / 2 - 12,
                            y: (UIScreen.hasRoundedCorners ? 44 : 16) + consoleSize.height / 2 + 12),
                    CGPoint(x: consoleSize.width / 2 + 12,
                            y: UIScreen.portraitSize.height - consoleSize.height / 2 - (keyboardHeight ?? consoleWindow?.safeAreaInsets.bottom ?? 0) - 12),
                    CGPoint(x: UIScreen.portraitSize.width - consoleSize.width / 2 - 12,
                            y: UIScreen.portraitSize.height - consoleSize.height / 2 - (keyboardHeight ?? consoleWindow?.safeAreaInsets.bottom ?? 0) - 12)]
        } else {
            return [CGPoint(x: UIScreen.portraitSize.width / 2,
                            y: (UIScreen.hasRoundedCorners ? 44 : 16) + consoleSize.height / 2 + 12),
                    CGPoint(x: UIScreen.portraitSize.width / 2,
                            y: UIScreen.portraitSize.height - consoleSize.height / 2 - (keyboardHeight ?? consoleWindow?.safeAreaInsets.bottom ?? 0) - 12)]
        }
    }
    
    lazy var initialViewLocation: CGPoint = .zero
    
    func configureConsole() {
        consoleSize = CGSize(width: UserDefaults.standard.object(forKey: "LocalConsole_Width") as? CGFloat ?? consoleSize.width,
                             height: UserDefaults.standard.object(forKey: "LocalConsole_Height") as? CGFloat ?? consoleSize.height)
        
        consoleView.backgroundColor = .black
        
        consoleView.layer.shadowRadius = 16
        consoleView.layer.shadowOpacity = 0.5
        consoleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        consoleView.center = possibleEndpoints.first!
        consoleView.alpha = 0
        
        consoleView.layer.cornerRadius = 22
        consoleView.layer.cornerCurve = .continuous
        
        let borderView = UIView()
        borderView.frame = CGRect(x: -1, y: -1,
                                   width: consoleSize.width + 2,
                                   height: consoleSize.height + 2)
        borderView.layer.borderWidth = 1
        borderView.layer.borderColor = UIColor(white: 1, alpha: 0.08).cgColor
        borderView.layer.cornerRadius = consoleView.layer.cornerRadius + 1
        borderView.layer.cornerCurve = .continuous
        borderView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        consoleView.addSubview(borderView)
        
        // Configure text view.
        consoleTextView.frame = CGRect(x: 2, y: 2, width: consoleSize.width - 4, height: consoleSize.height - 4)
        consoleTextView.isEditable = false
        consoleTextView.backgroundColor = .clear
        consoleTextView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        
        consoleTextView.isSelectable = false
        consoleTextView.showsVerticalScrollIndicator = false
        consoleTextView.contentInsetAdjustmentBehavior = .never
        consoleView.addSubview(consoleTextView)
        
        consoleTextView.layer.cornerRadius = consoleView.layer.cornerRadius - 2
        consoleTextView.layer.cornerCurve = .continuous
        
        // Configure gesture recognizers.
        panRecognizer.maximumNumberOfTouches = 1
        panRecognizer.delegate = self
        
        let tapRecognizer = UITapStartEndGestureRecognizer(target: self, action: #selector(consolePiPTapStartEnd(recognizer:)))
        tapRecognizer.delegate = self
        
        longPressRecognizer.minimumPressDuration = 0.1
        
        consoleView.addGestureRecognizer(panRecognizer)
        consoleView.addGestureRecognizer(tapRecognizer)
        consoleView.addGestureRecognizer(longPressRecognizer)
        
        // Prepare menu button.
        let diameter = CGFloat(28)
        
        // This tuned button frame is used to adjust where the menu appears.
        menuButton = UIButton(frame: CGRect(x: consoleView.bounds.width - 44,
                                            y: consoleView.bounds.height - 36,
                                            width: 44,
                                            height: 36 + 4 /*Offests the context menu by the desired amount*/))
        menuButton.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin]
        
        let circleFrame = CGRect(
            x: menuButton.bounds.width - diameter - (consoleView.layer.cornerRadius - diameter / 2),
            y: menuButton.bounds.height - diameter - (consoleView.layer.cornerRadius - diameter / 2) - 4,
            width: diameter, height: diameter)
        
        let circle = UIView(frame: circleFrame)
        circle.backgroundColor = UIColor(white: 0.2, alpha: 0.95)
        circle.layer.cornerRadius = diameter / 2
        circle.isUserInteractionEnabled = false
        menuButton.addSubview(circle)
        
        let ellipsisImage = UIImageView(image: UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)))
        ellipsisImage.frame.size = circle.bounds.size
        ellipsisImage.contentMode = .center
        circle.addSubview(ellipsisImage)
        
        menuButton.tintColor = UIColor(white: 1, alpha: 0.75)
        menuButton.menu = makeMenu()
        menuButton.showsMenuAsPrimaryAction = true
        consoleView.addSubview(menuButton)
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
    }
    
    /// Adds a LocalConsole window to the app's main scene.
    func configureWindow() {
        var windowSceneFound = false
        
        // Configure console window.
        func fetchWindowScene() {
            let windowScene = UIApplication.shared
                .connectedScenes
                .filter { $0.activationState == .foregroundActive }
                .first
            
            if let windowScene = windowScene as? UIWindowScene {
                
                windowSceneFound = true
                
                consoleWindow = ConsoleWindow(windowScene: windowScene)
                consoleWindow?.frame = UIScreen.main.bounds
                consoleWindow?.windowLevel = UIWindow.Level.statusBar
                consoleWindow?.isHidden = false
                consoleWindow?.addSubview(consoleView)
                
                UIWindow.swizzleStatusBarAppearanceOverride
            }
        }
        
        fetchWindowScene()
        
        /// Ensures the window is configured (i.e. scene has been found). If not, delay and wait for a scene to prepare itself, then try again.
        for i in 1...10 {
            
            let delay = Double(i) / 10
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
                
                guard !windowSceneFound else { return }
                
                fetchWindowScene()
                
                if isVisible {
                    isVisible = false
                    consoleView.layer.removeAllAnimations()
                    isVisible = true
                }
            }
        }
    }
    
    // MARK: - Public
    
    public var isVisible = false {
        didSet {
            guard oldValue != isVisible else { return }
            
            if isVisible {
                
                if !isConsoleConfigured {
                    configureWindow()
                    configureConsole()
                    isConsoleConfigured = true
                }
                
                commitTextChanges(requestMenuUpdate: true)
                
                consoleView.transform = .init(scaleX: 0.9, y: 0.9)
                UIViewPropertyAnimator(duration: 0.5, dampingRatio: 0.6) { [self] in
                    consoleView.transform = .init(scaleX: 1, y: 1)
                }.startAnimation()
                UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
                    consoleView.alpha = 1
                }.startAnimation()
                
                let animation = CABasicAnimation(keyPath: "shadowOpacity")
                animation.fromValue = 0
                animation.toValue = 0.5
                animation.duration = 0.6
                consoleView.layer.add(animation, forKey: animation.keyPath)
                consoleView.layer.shadowOpacity = 0.5
                
            } else {
                UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
                    consoleView.transform = .init(scaleX: 0.9, y: 0.9)
                }.startAnimation()
                
                UIViewPropertyAnimator(duration: 0.3, dampingRatio: 1) { [self] in
                    consoleView.alpha = 0
                }.startAnimation()
            }
        }
    }
    
    private var _hasRelayedOffsetChange = false
    
    /// Print items to the console view.
    public func print(_ items: Any) {
        if currentText == "" {
            currentText = "\(items)"
        } else {
            currentText = currentText + "\n\(items)"
        }
    }
    
    /// Clear text in the console view.
    public func clear() {
        currentText = ""
    }
    
    /// Copy the console view text to the device's clipboard.
    public func copy() {
        UIPasteboard.general.string = consoleTextView.text
    }
    
    // MARK: - Private
    
    
    // MARK: Handle keyboard show/hide.
    private var keyboardHeight: CGFloat? = nil {
        didSet {
            
            if consoleView.center != possibleEndpoints[0] && consoleView.center != possibleEndpoints[1] {
                let nearestTargetPosition = nearestTargetTo(consoleView.center, possibleTargets: possibleEndpoints.suffix(2))
                
                UIViewPropertyAnimator(duration: 0.55, dampingRatio: 1) {
                    self.consoleView.center = nearestTargetPosition
                }.startAnimation()
            }
        }
    }
    
    @objc func keyboardWillShow(_ notification: Notification) {
        if let keyboardFrame: NSValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
            let keyboardRectangle = keyboardFrame.cgRectValue
            self.keyboardHeight = keyboardRectangle.height
        }
    }
    
    @objc func keyboardWillHide() {
        keyboardHeight = nil
    }
    
    private var debugBordersEnabled = false {
        didSet {
            
            UIView.swizzleDebugBehaviour_UNTRACKABLE_TOGGLE()
            
            guard debugBordersEnabled else {
                GLOBAL_BORDER_TRACKERS.forEach {
                    $0.deactivate()
                }
                GLOBAL_BORDER_TRACKERS = []
                return
            }
            
            func subviewsRecursive(in _view: UIView) -> [UIView] {
                return _view.subviews + _view.subviews.flatMap { subviewsRecursive(in: $0) }
            }
            
            var allViews: [UIView] = []
            
            for window in UIApplication.shared.windows {
                allViews.append(contentsOf: subviewsRecursive(in: window))
            }
            allViews.forEach {
                let tracker = BorderManager(view: $0)
                GLOBAL_BORDER_TRACKERS.append(tracker)
                tracker.activate()
            }
        }
    }
    
    var dynamicReportTimer: Timer? {
        willSet { dynamicReportTimer?.invalidate() }
    }
    
    func systemReport() {
        DispatchQueue.main.async { [self] in
            
            if currentText != "" { print("\n") }
            
            dynamicReportTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                var _currentText = currentText
                
                let range: NSRange = {
                    if _currentText.count <= 2500 {
                        return NSMakeRange(0, _currentText.count)
                    }
                    return NSMakeRange(_currentText.count - 2500, 2500)
                }()
                
                let regex0 = try! NSRegularExpression(pattern: "Thermal State:      .*", options: NSRegularExpression.Options.caseInsensitive)
                _currentText = regex0.stringByReplacingMatches(in: _currentText, options: [], range: range, withTemplate: "Thermal State:      \(SystemReport.shared.thermalState)")
                
                let regex1 = try! NSRegularExpression(pattern: "System Uptime:      .*", options: NSRegularExpression.Options.caseInsensitive)
                _currentText = regex1.stringByReplacingMatches(in: _currentText, options: [], range: range, withTemplate: "System Uptime:      \(ProcessInfo.processInfo.systemUptime.formattedString!)")
                
                let regex2 = try! NSRegularExpression(pattern: "Low Power Mode:     .*", options: NSRegularExpression.Options.caseInsensitive)
                _currentText = regex2.stringByReplacingMatches(in: _currentText, options: [], range: range, withTemplate: "Low Power Mode:     \(ProcessInfo.processInfo.isLowPowerModeEnabled)")
                
                if currentText != _currentText {
                    currentText = _currentText
                } else {
                    timer.invalidate()
                }
            }
            
            print(
                  """
                  Model Name:         \(SystemReport.shared.gestaltMarketingName)
                  Model Identifier:   \(SystemReport.shared.gestaltModelIdentifier)
                  Architecture:       \(SystemReport.shared.gestaltArchitecture)
                  Firmware:           \(SystemReport.shared.gestaltFirmwareVersion)
                  Kernel Version:     \(SystemReport.shared.kernel) \(SystemReport.shared.kernelVersion)
                  System Version:     \(SystemReport.shared.versionString)
                  OS Compile Date:    \(SystemReport.shared.compileDate)
                  Memory:             \(round(100 * Double(ProcessInfo.processInfo.physicalMemory) * pow(10, -9)) / 100) GB
                  Processor Cores:    \(Int(ProcessInfo.processInfo.processorCount))
                  Thermal State:      \(SystemReport.shared.thermalState)
                  System Uptime:      \(ProcessInfo.processInfo.systemUptime.formattedString!)
                  Low Power Mode:     \(ProcessInfo.processInfo.isLowPowerModeEnabled)
                  """
            )
        }
    }
    
    func displayReport() {
        DispatchQueue.main.async { [self] in
            
            if currentText != "" { print("\n") }
            
            print(
                  """
                  Screen Size:            \(UIScreen.main.bounds.size)
                  Screen Corner Radius:   \(UIScreen.main.value(forKey: "_displ" + "ayCorn" + "erRa" + "dius") as! CGFloat)
                  Screen Scale:           \(UIScreen.main.scale)
                  Max Frame Rate:         \(UIScreen.main.maximumFramesPerSecond) Hz
                  Brightness:             \(String(format: "%.2f", UIScreen.main.brightness))
                  """
            )
        }
    }
    
    @objc func toggleLock() {
        scrollLocked.toggle()
    }
    
    func commitTextChanges(requestMenuUpdate menuUpdateRequested: Bool) {
        
        if consoleTextView.contentOffset.y > consoleTextView.contentSize.height - consoleTextView.bounds.size.height - 20
            || _hasRelayedOffsetChange == false {
            
            consoleTextView.pendingOffsetChange = true
            _hasRelayedOffsetChange = true
        }
        
        consoleTextView.text = currentText
        
        setAttributedText(currentText)
        
        if menuUpdateRequested {
            // Update the context menu to show the clipboard/clear actions.
            menuButton.menu = makeMenu()
        }
    }
    
    func setAttributedText(_ string: String) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = 7
        
        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold, design: .monospaced)
        ]
        
        consoleTextView.attributedText = NSAttributedString(string: string, attributes: attributes)
    }
    
    func makeMenu() -> UIMenu {
        
        let copy = UIAction(title: "Copy",
                                       image: UIImage(systemName: "doc.on.doc"), handler: { _ in
                                        self.copy()
                                       })
        
        let resize = UIAction(title: "Resize Console",
                              image: UIImage(systemName: "arrow.left.and.right.square"), handler: { _ in
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    ResizeController.shared.isActive.toggle()
                                    ResizeController.shared.platterView.reveal()
                                }
                              })
        
        let clear = UIAction(title: "Clear Console",
                             image: UIImage(systemName: "xmark.square"), handler: { _ in
                                self.clear()
                             })
        
        let consoleActions = UIMenu(title: "", options: .displayInline, children: [clear, resize])
        
        var frameSymbol = "rectangle.3.offgrid"
        if #available(iOS 15, *) {
            frameSymbol = "square.inset.filled"
        }
        
        let viewFrames = UIAction(title: debugBordersEnabled ? "Hide View Frames" : "Show View Frames",
                                  image: UIImage(systemName: frameSymbol), handler: { _ in
                                    self.debugBordersEnabled.toggle()
                                    self.menuButton.menu = self.makeMenu()
                                  })
        
        let systemReport = UIAction(title: "System Report",
                                  image: UIImage(systemName: "cpu"), handler: { _ in
                                    self.systemReport()
                                  })
        
        // Show the right glyph for the current device being used.
        let deviceSymbol: String = {
            
            let hasHomeButton = UIScreen.main.value(forKey: "_displ" + "ayCorn" + "erRa" + "dius") as! CGFloat == 0
            
            if UIDevice.current.userInterfaceIdiom == .pad {
                if hasHomeButton {
                    return "ipad.homebutton"
                } else {
                    return "ipad"
                }
            } else if UIDevice.current.userInterfaceIdiom == .phone {
                if hasHomeButton {
                    return "iphone.homebutton"
                } else {
                    return "iphone"
                }
            } else {
                return "rectangle"
            }
        }()
        
        let displayReport = UIAction(title: "Display Report",
                                  image: UIImage(systemName: deviceSymbol), handler: { _ in
                                    self.displayReport()
                                  })
        
        let respring = UIAction(title: "Restart Spring" + "Board",
                                image: UIImage(systemName: "apps.iphone"), handler: { _ in
                                    guard let window = UIApplication.shared.windows.first else { return }
                                    
                                    window.layer.cornerRadius = UIScreen.main.value(forKey: "_displ" + "ayCorn" + "erRa" + "dius") as! CGFloat
                                    window.layer.masksToBounds = true
                                    
                                    let animator = UIViewPropertyAnimator(duration: 0.5, dampingRatio: 1) {
                                        window.transform = .init(scaleX: 0.96, y: 0.96)
                                        window.alpha = 0
                                    }
                                    animator.addCompletion { _ in
                                        while true {
                                            window.snapshotView(afterScreenUpdates: false)
                                        }
                                    }
                                    animator.startAnimation()
                                })
        let debugActions = UIMenu(title: "", options: .displayInline,
                                  children: [UIMenu(title: "Debug", image: UIImage(systemName: "ant"),
                                                    children: [viewFrames, systemReport, displayReport, respring])])
        
        var menuContent: [UIMenuElement] = []
        
        if consoleTextView.text != "" {
            menuContent.append(contentsOf: [copy, consoleActions])
        } else {
            menuContent.append(resize)
        }
        menuContent.append(debugActions)
        
        return UIMenu(title: "", children: menuContent)
    }
    
    @objc func longPressAction(recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            feedbackGenerator.selectionChanged()
            
            scrollLocked = false
            
            UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
                consoleView.transform = .init(scaleX: 1.04, y: 1.04)
                consoleTextView.alpha = 0.5
            }.startAnimation()
        case .cancelled, .ended:
            
            scrollLocked = true
            
            UIViewPropertyAnimator(duration: 0.8, dampingRatio: 0.5) { [self] in
                consoleView.transform = .init(scaleX: 1, y: 1)
            }.startAnimation()
            
            UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
                consoleTextView.alpha = 1
            }.startAnimation()
        default: break
        }
    }
    
    @objc func consolePiPPanner(recognizer: UIPanGestureRecognizer) {
        
        if recognizer.state == .began {
            initialViewLocation = consoleView.center
        }
        
        guard !scrollLocked else { return }
        
        let translation = recognizer.translation(in: consoleView.superview)
        let velocity = recognizer.velocity(in: consoleView.superview)
        
        switch recognizer.state {
        case .changed:
            
            consoleView.center.x = initialViewLocation.x + translation.x
            consoleView.center.y = initialViewLocation.y + translation.y
            
        case .ended, .cancelled:
            
            // After the PiP is thrown, determine the best corner and re-target it there.
            let decelerationRate = UIScrollView.DecelerationRate.normal.rawValue
            
            let projectedPosition = CGPoint(
                x: consoleView.center.x + project(initialVelocity: velocity.x, decelerationRate: decelerationRate),
                y: consoleView.center.y + project(initialVelocity: velocity.y, decelerationRate: decelerationRate)
            )
            
            let nearestTargetPosition = nearestTargetTo(projectedPosition, possibleTargets: possibleEndpoints)
            
            let relativeInitialVelocity = CGVector(
                dx: relativeVelocity(forVelocity: velocity.x, from: consoleView.center.x, to: nearestTargetPosition.x),
                dy: relativeVelocity(forVelocity: velocity.y, from: consoleView.center.y, to: nearestTargetPosition.y)
            )
            
            let timingParameters = UISpringTimingParameters(damping: 1, response: 0.4, initialVelocity: relativeInitialVelocity)
            let positionAnimator = UIViewPropertyAnimator(duration: 0, timingParameters: timingParameters)
            positionAnimator.addAnimations { [self] in
                consoleView.center = nearestTargetPosition
            }
            positionAnimator.startAnimation()
            
        default: break
        }
    }
    
    // Animate touch down.
    func consolePiPTouchDown() {
        UIViewPropertyAnimator(duration: 1, dampingRatio: 0.5) { [self] in
            consoleView.transform = .init(scaleX: 0.96, y: 0.96)
        }.startAnimation()
        
        UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
            if !scrollLocked {
                consoleView.backgroundColor = #colorLiteral(red: 0.1331297589, green: 0.1331297589, blue: 0.1331297589, alpha: 1)
            }
        }.startAnimation()
    }
    
    // Animate touch up.
    func consolePiPTouchUp() {
        UIViewPropertyAnimator(duration: 0.8, dampingRatio: 0.4) { [self] in
            consoleView.transform = .init(scaleX: 1, y: 1)
        }.startAnimation()
        
        UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
            consoleTextView.alpha = 1
        }.startAnimation()
        
        UIViewPropertyAnimator(duration: 0.75, dampingRatio: 1) { [self] in
            consoleView.backgroundColor = .black
        }.startAnimation()
    }
    
    // Simulataneously listen to all gesture recognizers.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    @objc func consolePiPTapStartEnd(recognizer: UITapStartEndGestureRecognizer) {
        switch recognizer.state {
        case .began:
            consolePiPTouchDown()
        case .cancelled:
            consolePiPTouchUp()
        case .changed:
            break
        case .ended:
            consolePiPTouchUp()
        case .failed:
            consolePiPTouchUp()
        case .possible:
            consolePiPTouchUp()
        @unknown default:
            break
        }
    }
}

// Custom window for the console to appear above other windows while passing touches down.
class ConsoleWindow: UIWindow {
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        
        if let hitView = super.hitTest(point, with: event) {
            return hitView.isKind(of: ConsoleWindow.self) ? nil : hitView
        }
        return super.hitTest(point, with: event)
    }
}


import UIKit.UIGestureRecognizerSubclass

public class UITapStartEndGestureRecognizer: UITapGestureRecognizer {
    override public func touchesBegan(_ touches: Set<UITouch>, with: UIEvent) {
        self.state = .began
    }
    override public func touchesMoved(_ touches: Set<UITouch>, with: UIEvent) {
        self.state = .changed
    }
    override public func touchesEnded(_ touches: Set<UITouch>, with: UIEvent) {
        self.state = .ended
    }
}

// MARK: Fun hacks!
extension UIView {
    /// Swizzle UIView to use custom frame system when needed.
    static func swizzleDebugBehaviour_UNTRACKABLE_TOGGLE() {
        guard let originalMethod = class_getInstanceMethod(UIView.self, #selector(layoutSubviews)),
              let swizzledMethod = class_getInstanceMethod(UIView.self, #selector(swizzled_layoutSubviews)) else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    @objc func swizzled_layoutSubviews() {
        swizzled_layoutSubviews()
        
        let tracker = BorderManager(view: self)
        GLOBAL_BORDER_TRACKERS.append(tracker)
        tracker.activate()
    }
}

extension UIWindow {
    
    /// Make sure this window does not have control over the status bar appearance.
    static let swizzleStatusBarAppearanceOverride: Void = {
        guard let originalMethod = class_getInstanceMethod(UIWindow.self, NSSelectorFromString("_can" + "Affect" + "Sta" + "tus" + "Bar" + "Appe" + "arance")),
              let swizzledMethod = class_getInstanceMethod(UIWindow.self, #selector(swizzled_statusBarAppearance))
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()
    
    @objc func swizzled_statusBarAppearance() -> Bool {
        return isKeyWindow
    }
}

//#endif

class InvertedTextView: UITextView {
    
    var pendingOffsetChange = false
    
    // Thanks to WWDC21 Lab!
    override func layoutSubviews() {
        super.layoutSubviews()

        if panGestureRecognizer.numberOfTouches == 0 && pendingOffsetChange {
            contentOffset.y = contentSize.height - bounds.size.height
        } else {
            pendingOffsetChange = false
        }
    }
    
    var cancelNextContentSizeDidSet = false
    
    override var contentSize: CGSize {
        didSet {
            cancelNextContentSizeDidSet = true
            
            if contentSize.height < bounds.size.height {
                contentInset.top = bounds.size.height - contentSize.height
            } else {
                contentInset.top = 0
            }
        }
    }
}

extension TimeInterval {
    var formattedString: String? {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter.string(from: self)
    }
}

fileprivate func _debugPrint(_ items: Any) {
    print(items)
}
