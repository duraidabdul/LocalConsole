//
//  LocalConsole.swift
//
//  Created by Duraid Abdul.
//  Copyright © 2021 Duraid Abdul. All rights reserved.
//

import UIKit
import SwiftUI

var GLOBAL_BORDER_TRACKERS: [BorderManager] = []

@available(iOSApplicationExtension, unavailable)
public class LCManager: NSObject, UIGestureRecognizerDelegate {
    
    public static let shared = LCManager()
    
    /// Set the font size. The font can be set to a minimum value of 5.0 and a maximum value of 20.0. The default value is 8.
    public var fontSize: CGFloat = 8 {
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
    
    let defaultConsoleSize = CGSize(width: 240, height: 148)
    
    lazy var borderView = UIView()
    
    var lumaWidthAnchor: NSLayoutConstraint!
    var lumaHeightAnchor: NSLayoutConstraint!
    
    lazy var lumaView: LumaView = {
        let lumaView = LumaView()
        lumaView.foregroundView.backgroundColor = .black
        lumaView.layer.cornerRadius = consoleView.layer.cornerRadius
        
        consoleView.addSubview(lumaView)
        
        lumaView.translatesAutoresizingMaskIntoConstraints = false
        
        lumaWidthAnchor = lumaView.widthAnchor.constraint(equalTo: consoleView.widthAnchor)
        lumaHeightAnchor = lumaView.heightAnchor.constraint(equalToConstant: consoleView.frame.size.height)
        
        NSLayoutConstraint.activate([
            lumaWidthAnchor,
            lumaHeightAnchor,
            lumaView.centerXAnchor.constraint(equalTo: consoleView.centerXAnchor),
            lumaView.centerYAnchor.constraint(equalTo: consoleView.centerYAnchor)
        ])
        
        return lumaView
    }()
    
    lazy var unhideButton: UIButton = {
        let button = UIButton()
        
        button.addAction(UIAction(handler: { [self] _ in
            UIViewPropertyAnimator(duration: 0.5, dampingRatio: 1) {
                consoleView.center = nearestTargetTo(consoleView.center, possibleTargets: possibleEndpoints.dropLast())
            }.startAnimation()
            grabberMode = false
            
            UserDefaults.standard.set(consoleView.center.x, forKey: "LocalConsole_X")
            UserDefaults.standard.set(consoleView.center.y, forKey: "LocalConsole_Y")
        }), for: .touchUpInside)
        
        consoleView.addSubview(button)
        
        button.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalTo: consoleView.widthAnchor),
            button.heightAnchor.constraint(equalTo: consoleView.heightAnchor),
            button.centerXAnchor.constraint(equalTo: consoleView.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: consoleView.centerYAnchor)
        ])
        
        button.isHidden = true
        
        return button
    }()
    
    /// The fixed size of the console view.
    lazy var consoleSize = defaultConsoleSize {
        didSet {
            consoleView.frame.size = consoleSize
            
            // Update text view width.
            if consoleView.frame.size.width > ResizeController.kMaxConsoleWidth {
                consoleTextView.frame.size.width = ResizeController.kMaxConsoleWidth - 2
            } else if consoleView.frame.size.width < ResizeController.kMinConsoleWidth {
                consoleTextView.frame.size.width = ResizeController.kMinConsoleWidth - 2
            } else {
                consoleTextView.frame.size.width = consoleSize.width - 2
            }
            
            // Update text view height.
            if consoleView.frame.size.height > ResizeController.kMaxConsoleHeight {
                consoleTextView.frame.size.height = ResizeController.kMaxConsoleHeight - 2
                + (consoleView.frame.size.height - ResizeController.kMaxConsoleHeight) * 2 / 3
            } else if consoleView.frame.size.height < ResizeController.kMinConsoleHeight {
                consoleTextView.frame.size.height = ResizeController.kMinConsoleHeight - 2
                + (consoleView.frame.size.height - ResizeController.kMinConsoleHeight) * 2 / 3
            } else {
                consoleTextView.frame.size.height = consoleSize.height - 2
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
    lazy var viewController = UIViewController()
    lazy var consoleView = viewController.view!
    
    /// Text view that displays printed items.
    lazy var consoleTextView = InvertedTextView()
    
    /// Button that reveals menu.
    lazy var menuButton = UIButton()
    
    /// Tracks whether the PiP console is in text view scroll mode or pan mode.
    var scrollLocked = true
    
    /// Feedback generator for the long press action.
    lazy var feedbackGenerator = UISelectionFeedbackGenerator()
    
    lazy var panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(consolePiPPanner(recognizer:)))
    lazy var longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressAction(recognizer:)))
    
    /// Gesture endpoints. Each point represents a corner of the screen. TODO: Handle screen rotation.
    var possibleEndpoints: [CGPoint] {
        
        if consoleSize.width < UIScreen.portraitSize.width - 112 {
            
            // Four endpoints, one for each corner.
            var endpoints = [
                
                // Top endpoints.
                CGPoint(x: consoleSize.width / 2 + 12,
                        y: (UIScreen.hasRoundedCorners ? 38 : 16) + consoleSize.height / 2 + 12),
                CGPoint(x: UIScreen.portraitSize.width - consoleSize.width / 2 - 12,
                        y: (UIScreen.hasRoundedCorners ? 38 : 16) + consoleSize.height / 2 + 12),
                
                // Bottom endpoints.
                CGPoint(x: consoleSize.width / 2 + 12,
                        y: UIScreen.portraitSize.height - consoleSize.height / 2 - (keyboardHeight ?? consoleWindow?.safeAreaInsets.bottom ?? 0) - 12),
                CGPoint(x: UIScreen.portraitSize.width - consoleSize.width / 2 - 12,
                        y: UIScreen.portraitSize.height - consoleSize.height / 2 - (keyboardHeight ?? consoleWindow?.safeAreaInsets.bottom ?? 0) - 12)]
            
            if consoleView.frame.minX <= 0 {
                
                // Left edge endpoints.
                endpoints = [endpoints[0], endpoints[2]]
                
                // Left edge hiding endpoints.
                if consoleView.center.y < (UIScreen.portraitSize.height - (temporaryKeyboardHeightValueTracker ?? 0)) / 2 {
                    endpoints.append(CGPoint(x: -consoleSize.width / 2 + 28,
                                             y: endpoints[0].y))
                } else {
                    endpoints.append(CGPoint(x: -consoleSize.width / 2 + 28,
                                             y: endpoints[1].y))
                }
            } else if consoleView.frame.maxX >= UIScreen.portraitSize.width {
                
                // Right edge endpoints.
                endpoints = [endpoints[1], endpoints[3]]
                
                // Right edge hiding endpoints.
                if consoleView.center.y < (UIScreen.portraitSize.height - (temporaryKeyboardHeightValueTracker ?? 0)) / 2 {
                    endpoints.append(CGPoint(x: UIScreen.portraitSize.width + consoleSize.width / 2 - 28,
                                             y: endpoints[0].y))
                } else {
                    endpoints.append(CGPoint(x: UIScreen.portraitSize.width + consoleSize.width / 2 - 28,
                                             y: endpoints[1].y))
                }
            }
            
            return endpoints
            
        } else {
            
            // Two endpoints, one for the top, one for the bottom..
            var endpoints = [CGPoint(x: UIScreen.portraitSize.width / 2,
                                     y: (UIScreen.hasRoundedCorners ? 38 : 16) + consoleSize.height / 2 + 12),
                             CGPoint(x: UIScreen.portraitSize.width / 2,
                                     y: UIScreen.portraitSize.height - consoleSize.height / 2 - (keyboardHeight ?? consoleWindow?.safeAreaInsets.bottom ?? 0) - 12)]
            
            if consoleView.frame.minX <= 0 {
                
                // Left edge hiding endpoints.
                if consoleView.center.y < (UIScreen.portraitSize.height - (temporaryKeyboardHeightValueTracker ?? 0)) / 2 {
                    endpoints.append(CGPoint(x: -consoleSize.width / 2 + 28,
                                             y: endpoints[0].y))
                } else {
                    endpoints.append(CGPoint(x: -consoleSize.width / 2 + 28,
                                             y: endpoints[1].y))
                }
            } else if consoleView.frame.maxX >= UIScreen.portraitSize.width {
                
                // Right edge hiding endpoints.
                if consoleView.center.y < (UIScreen.portraitSize.height - (temporaryKeyboardHeightValueTracker ?? 0)) / 2 {
                    endpoints.append(CGPoint(x: UIScreen.portraitSize.width + consoleSize.width / 2 - 28,
                                             y: endpoints[0].y))
                } else {
                    endpoints.append(CGPoint(x: UIScreen.portraitSize.width + consoleSize.width / 2 - 28,
                                             y: endpoints[1].y))
                }
            }
            
            return endpoints
        }
    }
    
    lazy var initialViewLocation: CGPoint = .zero
    
    func configureConsole() {
        consoleSize = CGSize(width: UserDefaults.standard.object(forKey: "LocalConsole_Width") as? CGFloat ?? consoleSize.width,
                             height: UserDefaults.standard.object(forKey: "LocalConsole_Height") as? CGFloat ?? consoleSize.height)
        
        
        consoleView.layer.shadowRadius = 16
        consoleView.layer.shadowOpacity = 0.5
        consoleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        consoleView.alpha = 0
        
        consoleView.layer.cornerRadius = 24
        consoleView.layer.cornerCurve = .continuous
        
        let _ = lumaView
        
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
        consoleTextView.frame = CGRect(x: 1, y: 1, width: consoleSize.width - 2, height: consoleSize.height - 2)
        consoleTextView.isEditable = false
        consoleTextView.backgroundColor = .clear
        consoleTextView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        
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
        let diameter = CGFloat(30)
        
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
        
        let ellipsisImage = UIImageView(image: UIImage(systemName: "ellipsis",
                                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)))
        ellipsisImage.frame.size = circle.bounds.size
        ellipsisImage.contentMode = .center
        circle.addSubview(ellipsisImage)
        
        menuButton.tintColor = UIColor(white: 1, alpha: 0.75)
        menuButton.menu = makeMenu()
        menuButton.showsMenuAsPrimaryAction = true
        consoleView.addSubview(menuButton)
        
        let _ = unhideButton
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
    }
    
    /// Adds a LocalConsole window to the app's main scene.
    func configureWindow() {
        var windowSceneFound = false
        
        // Update console cached based on last-cached origin.
        func updateConsoleOrigin() {
            snapToCachedEndpoint()
            
            if consoleView.center.x < 0 || consoleView.center.x > UIScreen.portraitSize.width {
                grabberMode = true
                scrollLocked = !grabberMode
                
                consoleView.layer.removeAllAnimations()
                lumaView.layer.removeAllAnimations()
                menuButton.layer.removeAllAnimations()
                consoleTextView.layer.removeAllAnimations()
            }
        }
        
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
                
                updateConsoleOrigin()
            }
        }
        
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
    
    func snapToCachedEndpoint() {
        let cachedConsolePosition = CGPoint(x: UserDefaults.standard.object(forKey: "LocalConsole_X") as? CGFloat ?? possibleEndpoints.first!.x,
                                            y: UserDefaults.standard.object(forKey: "LocalConsole_Y") as? CGFloat ?? possibleEndpoints.first!.y)
        
        consoleView.center = cachedConsolePosition // Update console center so possibleEndpoints are calculated correctly.
        consoleView.center = nearestTargetTo(cachedConsolePosition, possibleTargets: possibleEndpoints)
    }
    
    // MARK: - Public
    
    public var isVisible = false {
        didSet {
            guard oldValue != isVisible else { return }
            
            if isVisible {
                
                if !isConsoleConfigured {
                    DispatchQueue.main.async { [self] in
                        configureWindow()
                        configureConsole()
                        isConsoleConfigured = true
                    }
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
    
    var grabberMode: Bool = false {
        
        didSet {
            guard oldValue != grabberMode else { return }
            
            if grabberMode {
                
                lumaView.layer.cornerRadius = consoleView.layer.cornerRadius
                lumaHeightAnchor.constant = consoleView.frame.size.height
                consoleView.layoutIfNeeded()
                
                UIViewPropertyAnimator(duration: 0.3, dampingRatio: 1) { [self] in
                    consoleTextView.alpha = 0
                    menuButton.alpha = 0
                    borderView.alpha = 0
                }.startAnimation()
                
                UIViewPropertyAnimator(duration: 0.5, dampingRatio: 1) { [self] in
                    lumaView.foregroundView.alpha = 0
                }.startAnimation()
                
                lumaWidthAnchor.constant = -34
                lumaHeightAnchor.constant = 96
                UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
                    lumaView.layer.cornerRadius = 8
                    consoleView.layoutIfNeeded()
                }.startAnimation(afterDelay: 0.06)
                
                consoleTextView.isUserInteractionEnabled = false
                unhideButton.isHidden = false
                
            } else {
                
                lumaHeightAnchor.constant = consoleView.frame.size.height
                lumaWidthAnchor.constant = 0
                UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
                    consoleView.layoutIfNeeded()
                    lumaView.layer.cornerRadius = consoleView.layer.cornerRadius
                }.startAnimation()
                
                UIViewPropertyAnimator(duration: 0.3, dampingRatio: 1) { [self] in
                    consoleTextView.alpha = 1
                    menuButton.alpha = 1
                    borderView.alpha = 1
                }.startAnimation(afterDelay: 0.2)
                
                UIViewPropertyAnimator(duration: 0.65, dampingRatio: 1) { [self] in
                    lumaView.foregroundView.alpha = 1
                }.startAnimation()
                
                consoleTextView.isUserInteractionEnabled = true
                unhideButton.isHidden = true
            }
        }
    }
    
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
    
    var temporaryKeyboardHeightValueTracker: CGFloat?
    
    // MARK: Handle keyboard show/hide.
    private var keyboardHeight: CGFloat? = nil {
        didSet {
            
            temporaryKeyboardHeightValueTracker = oldValue
            
            if consoleView.center != possibleEndpoints[0] && consoleView.center != possibleEndpoints[1] {
                let nearestTargetPosition = nearestTargetTo(consoleView.center, possibleTargets: possibleEndpoints.suffix(2))
                
                Swift.print(possibleEndpoints.suffix(2))
                
                UIViewPropertyAnimator(duration: 0.55, dampingRatio: 1) {
                    self.consoleView.center = nearestTargetPosition
                }.startAnimation()
            }
            
            temporaryKeyboardHeightValueTracker = keyboardHeight
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
                
                // To optimize performance, only scan the last 2500 characters of text for system report changes.
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
                    
                    // Invalidate the timer if there is no longer anything to update.
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
    
    func commitTextChanges(requestMenuUpdate menuUpdateRequested: Bool) {
        
        if consoleTextView.contentOffset.y > consoleTextView.contentSize.height - consoleTextView.bounds.size.height - 20 {
            
            // Weird, weird fix that makes the scroll view bottom pinning system work.
            consoleTextView.isScrollEnabled.toggle()
            consoleTextView.isScrollEnabled.toggle()
            
            consoleTextView.pendingOffsetChange = true
        }
        
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
            
            UIViewPropertyAnimator(duration: 0.5, dampingRatio: 1) {
                window.transform = .init(scaleX: 0.96, y: 0.96)
                window.alpha = 0
            }.startAnimation()
            
            // Concurrently run these snapshots to decrease the time to crash.
            for _ in 0...1000 {
                DispatchQueue.global(qos: .default).async {
                    
                    // This will cause jetsam to terminate SpringBoard.
                    while true {
                        window.snapshotView(afterScreenUpdates: false)
                    }
                }
            }
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
            
            guard !grabberMode else { return }
            
            feedbackGenerator.selectionChanged()
            
            scrollLocked = false
            
            UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
                consoleView.transform = .init(scaleX: 1.04, y: 1.04)
                consoleTextView.alpha = 0.5
                menuButton.alpha = 0.5
            }.startAnimation()
        case .cancelled, .ended:
            
            if !grabberMode { scrollLocked = true }
            
            UIViewPropertyAnimator(duration: 0.8, dampingRatio: 0.5) { [self] in
                consoleView.transform = .identity
            }.startAnimation()
            
            UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
                if !grabberMode {
                    consoleTextView.alpha = 1
                    menuButton.alpha = 1
                }
            }.startAnimation()
        default: break
        }
    }
    
    let consolePiPPanner_frameRateRequest = FrameRateRequest()
    
    @objc func consolePiPPanner(recognizer: UIPanGestureRecognizer) {
        
        if recognizer.state == .began {
            consolePiPPanner_frameRateRequest.isActive = true
            
            initialViewLocation = consoleView.center
        }
        
        guard !scrollLocked else { return }
        
        let translation = recognizer.translation(in: consoleView.superview)
        let velocity = recognizer.velocity(in: consoleView.superview)
        
        switch recognizer.state {
        case .changed:
            
            UIViewPropertyAnimator(duration: 0.175, dampingRatio: 1) { [self] in
                consoleView.center = CGPoint(x: initialViewLocation.x + translation.x,
                                             y: initialViewLocation.y + translation.y)
            }.startAnimation()
            
            if consoleView.frame.maxX > 30 && consoleView.frame.minX < UIScreen.portraitSize.width - 30 {
                grabberMode = false
            } else {
                grabberMode = true
            }
            
        case .ended, .cancelled:
            
            consolePiPPanner_frameRateRequest.isActive = true
            FrameRateRequest().perform(duration: 0.5)
            
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
            
            let timingParameters = UISpringTimingParameters(damping: 0.85, response: 0.45, initialVelocity: relativeInitialVelocity)
            let positionAnimator = UIViewPropertyAnimator(duration: 0, timingParameters: timingParameters)
            positionAnimator.addAnimations { [self] in
                consoleView.center = nearestTargetPosition
            }
            positionAnimator.startAnimation()
            
            UserDefaults.standard.set(nearestTargetPosition.x, forKey: "LocalConsole_X")
            UserDefaults.standard.set(nearestTargetPosition.y, forKey: "LocalConsole_Y")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.grabberMode = nearestTargetPosition.x < 0 || nearestTargetPosition.x > UIScreen.portraitSize.width
                self.scrollLocked = !self.grabberMode
            }
            
        default: break
        }
    }
    
    // Animate touch down.
    func consolePiPTouchDown() {
        guard !grabberMode else { return }
        
        UIViewPropertyAnimator(duration: 1.25, dampingRatio: 0.5) { [self] in
            consoleView.transform = .init(scaleX: 0.95, y: 0.95)
        }.startAnimation()
    }
    
    // Animate touch up.
    func consolePiPTouchUp() {
        UIViewPropertyAnimator(duration: 0.8, dampingRatio: 0.4) { [self] in
            consoleView.transform = .init(scaleX: 1, y: 1)
        }.startAnimation()
        
        UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
            if !grabberMode {
                consoleTextView.alpha = 1
                if !ResizeController.shared.isActive {
                    menuButton.alpha = 1
                }
            }
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
        case .changed:
            break
        case .ended, .cancelled, .possible, .failed:
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

class LumaView: UIView {
    lazy var visualEffectView: UIView = {
        Bundle(path: "/Sys" + "tem/Lib" + "rary/Private" + "Frameworks/Material" + "Kit." + "framework")!.load()
        
        let Pill = NSClassFromString("MT" + "Luma" + "Dodge" + "Pill" + "View") as! UIView.Type
        
        let pillView = Pill.init()
        
        enum Style: Int {
            case none = 0
            case thin = 1
            case gray = 2
            case black = 3
            case white = 4
        }
        
        enum BackgroundLuminance: Int {
            case unknown = 0
            case dark = 1
            case light = 2
        }
        
        pillView.setValue(2, forKey: "style")
        pillView.setValue(1, forKey: "background" + "Luminance")
        pillView.perform(NSSelectorFromString("_" + "update" + "Style"))
        
        addSubview(pillView)
        
        pillView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            pillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pillView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pillView.topAnchor.constraint(equalTo: topAnchor),
            pillView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        return pillView
    }()
    
    lazy var foregroundView: UIView = {
        let view = UIView()
        
        addSubview(view)
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        return view
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        let _ = visualEffectView
        let _ = foregroundView
        
        visualEffectView.isUserInteractionEnabled = false
        foregroundView.isUserInteractionEnabled = false
        
        layer.cornerCurve = .continuous
        clipsToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

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

// MARK: Frame Rate Request
/**
An object that allows you to manually request an increased display refresh rate on ProMotion devices.

*The display refresh rate does not exceed 60 Hz when low power mode is enabled.*

**Do not set an excessive duration. Doing so will negatively impact battery life.**
 
```
// Example
let request = FrameRateRequest(preferredFrameRate: 120,
                               duration: 0.4)
request.perform()
```
 */
class FrameRateRequest {
    
    lazy private var displayLink = CADisplayLink(target: self, selector: #selector(dummyFunction))
    
    var isActive: Bool = false {
        didSet {
            guard #available(iOS 15, *) else { return }
            guard isActive != oldValue else { return }
            
            if isActive {
                displayLink.add(to: .current, forMode: .common)
            } else {
                displayLink.remove(from: .current, forMode: .common)
            }
        }
    }
    
    /// Prepares your frame rate request parameters.
    init(preferredFrameRate: Float = Float(UIScreen.main.maximumFramesPerSecond)) {
        if #available(iOS 15, *) {
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: Float(UIScreen.main.maximumFramesPerSecond), preferred: preferredFrameRate)
        }
    }
    
    /// Perform frame rate request.
    func perform(duration: Double) {
        isActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [self] in
            isActive = false
        }
    }
    
    @objc private func dummyFunction() {}
}
