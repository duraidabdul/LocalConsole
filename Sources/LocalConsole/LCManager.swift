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
            
            UserDefaults.standard.set(consoleView.center.x, forKey: "LocalConsole.X")
            UserDefaults.standard.set(consoleView.center.y, forKey: "LocalConsole.Y")
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
            
            UserDefaults.standard.set(consoleSize.width, forKey: "LocalConsole.Width")
            UserDefaults.standard.set(consoleSize.height, forKey: "LocalConsole.Height")
        }
    }
    
    lazy var consoleViewController = ConsoleViewController()
    
    /// Note: The console always needs a parent view controller in order to display context menus. In this case, the parent controller will be the viewController.
    lazy var consoleView = UIView()
    
    /// Text view that displays printed items.
    lazy var consoleTextView = InvertedTextView() 
    
    /// Button that reveals menu.
    lazy var menuButton = ConsoleMenuButton()
    
    /// Tracks whether the PiP console is in text view scroll mode or pan mode.
    var scrollLocked = true
    
    /// Feedback generator for the long press action.
    lazy var feedbackGenerator = UIImpactFeedbackGenerator(style: .soft)
    
    lazy var panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(consolePiPPanner(recognizer:)))
    lazy var longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressAction(recognizer:)))
    
    /// Gesture endpoints. Each point represents a corner of the screen. TODO: Handle screen rotation.
    var possibleEndpoints: [CGPoint] {
        let screenSize = consoleViewController.view.frame.size
        
        // Must check for portrait mode manually here. UIDevice was reporting orientation incorrectly before.
        let isPortraitNotchedPhone = UIDevice.current.hasNotch && consoleViewController.view.frame.size.width < consoleViewController.view.frame.size.height
        
        // Fix incorrect reported orientation on phone.
        let isLandscapePhone = UIDevice.current.userInterfaceIdiom == .phone && consoleViewController.view.frame.width > consoleViewController.view.frame.height
        
        let isLandscapeLeftNotchedPhone = UIDevice.current.orientation == .landscapeLeft
        && UIDevice.current.userInterfaceIdiom == .phone
        && UIDevice.current.hasNotch
        && isLandscapePhone
        
        let isLandscapeRightNotchedPhone = UIDevice.current.orientation == .landscapeRight
        && UIDevice.current.userInterfaceIdiom == .phone
        && UIDevice.current.hasNotch
        && isLandscapePhone
        
        let safeAreaInsets = consoleViewController.view.safeAreaInsets
        
        let leftEndpointX = consoleSize.width / 2 + safeAreaInsets.left + (isLandscapePhone ? 4 : 12) + (isLandscapeRightNotchedPhone ? -16 : 0)
        let rightEndpointX = screenSize.width - (consoleSize.width / 2 + safeAreaInsets.right) - (isLandscapePhone ? 4 : 12) + (isLandscapeLeftNotchedPhone ? 16 : 0)
        let topEndpointY = consoleSize.height / 2 + safeAreaInsets.top + 12 + (isPortraitNotchedPhone ? -10 : 0)
        let bottomEndpointY = screenSize.height - consoleSize.height / 2 - (keyboardHeight ?? safeAreaInsets.bottom) - 12 + (isLandscapePhone ? 10 : 0)
        
        if consoleSize.width < screenSize.width - 112 {
            // Four endpoints, one for each corner.
            var endpoints = [
                CGPoint(x: leftEndpointX, y: topEndpointY),
                CGPoint(x: rightEndpointX, y: topEndpointY),
                CGPoint(x: leftEndpointX, y: bottomEndpointY),
                CGPoint(x: rightEndpointX, y: bottomEndpointY),
            ]
            
            if consoleView.frame.minX <= 0 {
                
                // Left edge endpoints.
                endpoints = [endpoints[0], endpoints[2]]
                
                // Left edge hiding endpoints.
                if !isLandscapeLeftNotchedPhone {
                    if consoleView.center.y < (screenSize.height - (temporaryKeyboardHeightValueTracker ?? 0)) / 2 {
                        endpoints.append(CGPoint(x: -consoleSize.width / 2 + 28,
                                                 y: endpoints[0].y))
                    } else {
                        endpoints.append(CGPoint(x: -consoleSize.width / 2 + 28,
                                                 y: endpoints[1].y))
                    }
                }
            } else if consoleView.frame.maxX >= screenSize.width {
                
                // Right edge endpoints.
                endpoints = [endpoints[1], endpoints[3]]
                
                // Right edge hiding endpoints.
                if !isLandscapeRightNotchedPhone {
                    if consoleView.center.y < (screenSize.height - (temporaryKeyboardHeightValueTracker ?? 0)) / 2 {
                        endpoints.append(CGPoint(x: screenSize.width + consoleSize.width / 2 - 28,
                                                 y: endpoints[0].y))
                    } else {
                        endpoints.append(CGPoint(x: screenSize.width + consoleSize.width / 2 - 28,
                                                 y: endpoints[1].y))
                    }
                }
            }
            
            return endpoints
            
        } else {
            // Two endpoints, one for the top, one for the bottom..
            var endpoints = [
                CGPoint(x: screenSize.width / 2, y: topEndpointY),
                CGPoint(x: screenSize.width / 2, y: bottomEndpointY)
            ]
            
            if consoleView.frame.minX <= 0 {
                
                // Left edge hiding endpoints.
                if consoleView.center.y < (screenSize.height - (temporaryKeyboardHeightValueTracker ?? 0)) / 2 {
                    endpoints.append(CGPoint(x: -consoleSize.width / 2 + 28,
                                             y: endpoints[0].y))
                } else {
                    endpoints.append(CGPoint(x: -consoleSize.width / 2 + 28,
                                             y: endpoints[1].y))
                }
            } else if consoleView.frame.maxX >= screenSize.width {
                
                // Right edge hiding endpoints.
                if consoleView.center.y < (screenSize.height - (temporaryKeyboardHeightValueTracker ?? 0)) / 2 {
                    endpoints.append(CGPoint(x: screenSize.width + consoleSize.width / 2 - 28,
                                             y: endpoints[0].y))
                } else {
                    endpoints.append(CGPoint(x: screenSize.width + consoleSize.width / 2 - 28,
                                             y: endpoints[1].y))
                }
            }
            
            return endpoints
        }
    }
    
    lazy var initialViewLocation: CGPoint = .zero
    
    func configureConsole() {
        consoleSize = CGSize(width: UserDefaults.standard.object(forKey: "LocalConsole.Width") as? CGFloat ?? consoleSize.width,
                             height: UserDefaults.standard.object(forKey: "LocalConsole.Height") as? CGFloat ?? consoleSize.height)
        
        
        consoleView.layer.shadowRadius = 16
        consoleView.layer.shadowOpacity = 0.5
        consoleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        consoleView.alpha = 0
        
        consoleView.layer.cornerRadius = 24
        consoleView.layer.cornerCurve = .continuous
        
        let _ = lumaView
        
        let borderWidth = 2 - 1 / consoleView.traitCollection.displayScale
        
        borderView.frame = CGRect(
            x: -borderWidth, y: -borderWidth,
            width: consoleSize.width + 2 * borderWidth,
            height: consoleSize.height + 2 * borderWidth
        )
        borderView.layer.borderWidth = borderWidth
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
        
        longPressRecognizer.minimumPressDuration = 0.3
        
        consoleView.addGestureRecognizer(panRecognizer)
        consoleView.addGestureRecognizer(tapRecognizer)
        consoleView.addGestureRecognizer(longPressRecognizer)
        
        // Prepare menu button.
        let diameter = CGFloat(30)
        
        // This tuned button frame is used to adjust where the menu appears.
        menuButton.frame = CGRect(
            x: consoleView.bounds.width - 44,
            y: consoleView.bounds.height - 36,
            width: 44,
            height: 36 + 4 /*Offests the context menu by the desired amount*/
        )
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
        
        let ellipsisImage = UIImageView(
            image: UIImage(
                systemName: "ellipsis",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            )
        )
        ellipsisImage.frame.size = circle.bounds.size
        ellipsisImage.contentMode = .center
        circle.addSubview(ellipsisImage)
        
        menuButton.tintColor = UIColor(white: 1, alpha: 0.8)
        menuButton.menu = makeMenu()
        menuButton.showsMenuAsPrimaryAction = true
        consoleView.addSubview(menuButton)
        
        let _ = unhideButton
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
    }
    
    /// Adds a consoleViewController to the app's main window.
    func configureConsoleViewController() {
        var windowFound = false
        
        // Update console cached based on last-cached origin.
        func updateConsoleOrigin() {
            snapToCachedEndpoint()
            
            if consoleView.center.x < 0 || consoleView.center.x > consoleViewController.view.frame.size.width {
                grabberMode = true
                scrollLocked = !grabberMode
                
                consoleView.layer.removeAllAnimations()
                lumaView.layer.removeAllAnimations()
                menuButton.layer.removeAllAnimations()
                consoleTextView.layer.removeAllAnimations()
            }
        }
        
        // Configure console window.
        func fetchWindow() -> UIWindow? {
            if #available(iOS 15.0, *) {
                let windowScene = UIApplication.shared
                    .connectedScenes
                    .filter { $0.activationState == .foregroundActive }
                    .first
                
                if let windowScene = windowScene as? UIWindowScene, let keyWindow = windowScene.keyWindow {
                    return keyWindow
                }
                return nil
            } else {
                return UIApplication.shared.windows.first
            }
            
        }
        
        func addConsoleToWindow(window: UIWindow) {
            
            window.addSubview(consoleViewController.view)
            window.rootViewController?.addChild(consoleViewController)
            
            consoleViewController.view = PassthroughView()
            consoleViewController.view.addSubview(consoleView)
            
            consoleViewController.view.frame = window.bounds
            consoleViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            
            updateConsoleOrigin()
            
            SwizzleTool().swizzleContextMenuReverseOrder()
            
            // Ensure console view always stays above other views.
            SwizzleTool().swizzleDidAddSubview {
                window.bringSubviewToFront(self.consoleViewController.view)
            }
        }
        
        /// Ensures the window is configured (i.e. scene has been found). If not, delay and wait for a scene to prepare itself, then try again.
        for i in 1...10 {
            let delay = Double(i) / 10
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
                
                guard !windowFound else { return }
                
                if let window = fetchWindow() {
                    windowFound = true
                    addConsoleToWindow(window: window)
                }
                
                if isVisible {
                    isVisible = false
                    consoleView.layer.removeAllAnimations()
                    isVisible = true
                }
            }
        }
    }
    
    func snapToCachedEndpoint() {
        let cachedConsolePosition = CGPoint(
            x: UserDefaults.standard.object(forKey: "LocalConsole.X") as? CGFloat ?? possibleEndpoints.first!.x,
            y: UserDefaults.standard.object(forKey: "LocalConsole.Y") as? CGFloat ?? possibleEndpoints.first!.y
        )
        
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
                        configureConsoleViewController()
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
    
    // Specify a UIMenu or UIAction to be included in the console's main menu.
    public var menu: UIMenuElement? = nil {
        didSet {
            menuButton.menu = makeMenu()
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
                    lumaView.layer.cornerRadius = 10
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
    
    @objc func handleDeviceOrientationChange(previousSize: CGSize) {
        
        // Cancel the panner console is being panned to allow for location manipulation.
        [LCManager.shared.panRecognizer, LCManager.shared.longPressRecognizer].forEach {
            $0.isEnabled.toggle(); $0.isEnabled.toggle()
        }
        
        if UIDevice.current.userInterfaceIdiom != .pad && ResizeController.shared.isActive {
            ResizeController.shared.isActive = false
            ResizeController.shared.platterView.dismiss()
        }
        
        if UIDevice.current.userInterfaceIdiom == .pad && ResizeController.shared.isActive {
            DispatchQueue.main.async {
                UIViewPropertyAnimator(duration: 0.6, dampingRatio: 1) {
                    LCManager.shared.consoleView.center = ResizeController.shared.consoleCenterPoint
                }.startAnimation(afterDelay: 0.05)
            }
        } else {
            let consoleView = LCManager.shared.consoleView
            
            let targetLocationEstimate: CGPoint = {
                var xPosition = consoleView.center.x
                var yPosition = consoleView.center.y
                
                if consoleView.center.x > previousSize.width / 2 {
                    xPosition += consoleViewController.view.frame.width - previousSize.width
                }
                
                if consoleView.center.y > previousSize.height / 2 {
                    yPosition += consoleViewController.view.frame.height - previousSize.height
                }
                
                return CGPoint(x: xPosition, y: yPosition)
            }()
            
            UIViewPropertyAnimator(duration: 0.6, dampingRatio: 1) {
                consoleView.center = targetLocationEstimate
            }.startAnimation(afterDelay: 0.05)
            
            DispatchQueue.main.async {
                // Update portrait orientation menu option for resize controller.
                LCManager.shared.menuButton.menu = LCManager.shared.makeMenu()
                
                // Reassess center of console based on target location estimate.
                UIViewPropertyAnimator(duration: 0.6, dampingRatio: 1) {
                    consoleView.center = nearestTargetTo(consoleView.center, possibleTargets: LCManager.shared.possibleEndpoints)
                }.startAnimation(afterDelay: 0.05)
                
                LCManager.shared.reassessGrabberMode()
            }
        }
    }
    
    var hasShortened = false
    
    public var isCharacterLimitDisabled = false
    public var isCharacterLimitWarningDisabled = false
    
    /// Print items to the console view.
    public func print(_ items: Any) {
        let _currentText: String = {
            if currentText == "" {
                return "\(items)"
            } else {
                return currentText + "\n\(items)"
            }
        }()
        
        // Cut down string if it exceeds 50,000 characters to keep text view running smoothly.
        if _currentText.count > 50000 && !isCharacterLimitDisabled {
            
            if !hasShortened && !isCharacterLimitWarningDisabled {
                hasShortened = true
                Swift.print("LocalConsole's content has exceeded 50,000 characters.\nTo maintain performance, LCManager cuts down the beginning of the printed content. To disable this behaviour, set LCManager.shared.isCharacterLimitDisabled to true.\nTo disable this warning, set LCManager.shared.isCharacterLimitWarningDisabled = true.")
                
            }
            
            let shortenedString = String(_currentText.suffix(50000))
            currentText = shortenedString.stringAfterFirstOccurenceOf(delimiter: "\n") ?? shortenedString
        } else {
            currentText = _currentText
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
            
            if possibleEndpoints.count > 2, consoleView.center != possibleEndpoints[0] && consoleView.center != possibleEndpoints[1] {
                let nearestTargetPosition = nearestTargetTo(consoleView.center, possibleTargets: possibleEndpoints.suffix(2))
                
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
        willSet {
            timerInvalidationCounter = 0
            dynamicReportTimer?.invalidate()
        }
    }
    
    var timerInvalidationCounter = 0
    
    func systemReport() {
        DispatchQueue.main.async { [self] in
            
            if currentText != "" { print("\n") }
            
            dynamicReportTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [self] timer in
                
                guard consoleTextView.panGestureRecognizer.numberOfTouches == 0 else { return }
                
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
                    
                    timerInvalidationCounter = 0
                    
                } else {
                    
                    timerInvalidationCounter += 1
                    
                    // It has been 2 seconds and values have not changed.
                    if timerInvalidationCounter == 2 {
                        
                        // Invalidate the timer if there is no longer anything to update.
                        dynamicReportTimer = nil
                    }
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
            
            let safeAreaInsets = consoleViewController.view.safeAreaInsets ?? .zero
            
            print(
                  """
                  Screen Size:       \(UIScreen.main.bounds.size)
                  Corner Radius:     \(UIScreen.main.value(forKey: "_displ" + "ayCorn" + "erRa" + "dius") as! CGFloat)
                  Screen Scale:      \(UIScreen.main.scale)
                  Max Frame Rate:    \(UIScreen.main.maximumFramesPerSecond) Hz
                  Brightness:        \(String(format: "%.2f", UIScreen.main.brightness))
                  
                  Safe Area Insets:  top:    \(String(describing: safeAreaInsets.top))
                                     left:   \(String(describing: safeAreaInsets.left))
                                     bottom: \(String(describing: safeAreaInsets.bottom))
                                     right:  \(String(describing: safeAreaInsets.right))
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
    
    // Displays all UserDefaults keys, including unneeded keys that are included by default.
    public var showAllUserDefaultsKeys = false
    
    func makeMenu() -> UIMenu {
        let share: UIAction = {
            // Something here causes a crash < iOS 15. Fall back to copy text for iOS 15 and below.
            if #available(iOS 16, *) {
                return UIAction(title: "Share Text...", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    let activityViewController = UIActivityViewController(
                        activityItems: [self.consoleTextView.text ?? ""],
                        applicationActivities: nil
                    )
                    self.consoleViewController.present(activityViewController, animated: true)
                }
            } else {
                return UIAction(title: "Copy Text", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = self.consoleTextView.text
                }
            }
        }()
        
        let resize = UIAction(title: "Resize Console", image: UIImage(systemName: "arrow.up.backward.and.arrow.down.forward")) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                ResizeController.shared.isActive.toggle()
                ResizeController.shared.platterView.reveal()
            }
        }
        
        // If device is phone in landscape, disable resize controller.
        if UIDevice.current.userInterfaceIdiom == .phone && consoleViewController.view.frame.width > consoleViewController.view.frame.height {
            resize.attributes = .disabled
            if #available(iOS 15, *) {
                resize.subtitle = "Portrait Orientation Only"
            }
        }
        
        let clear = UIAction(title: "Clear Console", image: UIImage(systemName: "delete.backward"), attributes: .destructive) { _ in
            self.clear()
        }
        
        var frameSymbol = "rectangle.3.offgrid"
        
        var debugActions: [UIMenuElement] = []
        
        if #available(iOS 15, *) {
            frameSymbol = "square.inset.filled"
            
            let deferredUserDefaultsList = UIDeferredMenuElement.uncached { completion in
                var actions: [UIAction] = []
                
                let keys: [String] = {
                    
                    if self.showAllUserDefaultsKeys {
                        return UserDefaults.standard.dictionaryRepresentation().map { $0.key }
                    }
                    
                    // Show keys the developer has added to the app (+ LocalConsole keys), excluding all of Apple's keys.
                    if let bundle: String = Bundle.main.bundleIdentifier {
                        let preferencePath: String = NSHomeDirectory() + "/Library/Preferences/\(bundle).plist"
                        
                        let _keys = NSDictionary(contentsOfFile: preferencePath)?.allKeys as! [String]
                        
                        return _keys.filter {
                            !$0.contains("LocalConsole.")
                        }
                    }
                    
                    return []
                }()
                
                if keys.isEmpty {
                    actions.append(
                        UIAction(title: "No Entries", attributes: .disabled, handler: { _ in })
                    )
                } else {
                    for key in keys.sorted(by: { $0.lowercased() < $1.lowercased() }) {
                        
                        // Old LocalConsole Key Cleanup
                        guard !key.contains("LocalConsole_") else {
                            UserDefaults.standard.removeObject(forKey: key)
                            continue
                        }
                        
                        if let value = UserDefaults.standard.value(forKey: key) {
                            let action = UIAction(title: key, image: nil) { _ in
                                let alertController = UIAlertController(title: key,
                                                                        message: nil,
                                                                        preferredStyle: .alert)
                                
                                let headerParagraphStyle = NSMutableParagraphStyle()
                                headerParagraphStyle.paragraphSpacing = 6
                                let contentParagraphStyle = NSMutableParagraphStyle()
                                
                                let attributes: [NSAttributedString.Key: Any] = [
                                    .paragraphStyle: contentParagraphStyle,
                                    .foregroundColor: UIColor.label,
                                    .font: UIFont.systemFont(ofSize: 13, weight: .semibold, design: .monospaced)
                                ]
                                
                                let attributedTitle: NSMutableAttributedString = {
                                    
                                    let attributedString = NSMutableAttributedString(string: "Key\n" + key, attributes: attributes)
                                    attributedString.addAttributes(
                                        [NSAttributedString.Key.foregroundColor : UIColor.label.withAlphaComponent(0.5),
                                         NSAttributedString.Key.paragraphStyle : headerParagraphStyle],
                                        range: NSRange(location: 0, length: 3))
                                    
                                    return attributedString
                                }()
                                
                                let attributedMessage: NSMutableAttributedString = {
                                    
                                    let attributedString = NSMutableAttributedString(string: "\nValue\n" + "\(value)", attributes: attributes)
                                    attributedString.addAttributes(
                                        [NSAttributedString.Key.foregroundColor : UIColor.label.withAlphaComponent(0.5),
                                         NSAttributedString.Key.paragraphStyle : headerParagraphStyle],
                                        range: NSRange(location: 0, length: 7))
                                    
                                    return attributedString
                                }()
                                
                                alertController.setValue(attributedTitle, forKey: "attributedTitle")
                                alertController.setValue(attributedMessage, forKey: "attributedMessage")
                                
                                alertController.addAction(UIAlertAction(title: "Copy Value", style: .default, handler: { _ in
                                    UIPasteboard.general.string = "\(value)"
                                }))
                                alertController.addAction(UIAlertAction(title: "Clear Value", style: .destructive, handler: { _ in
                                    UserDefaults.standard.removeObject(forKey: key)
                                }))
                                alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in
                                }))
                                
                                self.consoleViewController.present(alertController,
                                                            animated: true)
                            }
                            action.subtitle = "\(value)"
                            actions.append(action)
                        }
                    }
                    
                    
                    actions.append(
                        UIAction(title: "Clear Defaults",
                                 image: UIImage(systemName: "trash"), attributes: .destructive, handler: { _ in
                                     keys.forEach {
                                         UserDefaults.standard.removeObject(forKey: $0)
                                     }
                                 })
                    )
                }
                
                
                completion(actions)
            }
            
            let userDefaults = UIMenu(title: "UserDefaults", image: UIImage(systemName: "doc.badge.gearshape"), children: [deferredUserDefaultsList])
            
            debugActions.append(userDefaults)
        }
        
        
        let viewFrames = UIAction(
            title: debugBordersEnabled ? "Hide View Frames" : "Show View Frames",
            image: UIImage(systemName: frameSymbol)
        ) { _ in
            self.debugBordersEnabled.toggle()
            self.menuButton.menu = self.makeMenu()
        }
        
        let systemReport = UIAction(title: "System Report", image: UIImage(systemName: "cpu")) { _ in
            self.systemReport()
        }
        
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
        
        let displayReport = UIAction(title: "Display Report", image: UIImage(systemName: deviceSymbol)) { _ in
            self.displayReport()
        }
        
        let terminateApplication = UIAction(title: "Terminate App", image: UIImage(systemName: "xmark"), attributes: .destructive) { _ in
            UIApplication.shared.perform(NSSelectorFromString("terminateWithSuccess"))
        }
        
        let respring = UIAction(title: "Restart Spring" + "Board", image: UIImage(systemName: "arrowtriangle.backward"), attributes: .destructive) { _ in
            
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
                    
                    // This will cause jetsam to terminate backboardd.
                    while true {
                        window.snapshotView(afterScreenUpdates: false)
                    }
                }
            }
        }
        
        debugActions.append(contentsOf: [viewFrames, systemReport, displayReport])
        let destructActions = [terminateApplication , respring]
        
        let debugMenu = UIMenu(
            title: "Debug", image: UIImage(systemName: "ant"),
            children: [
                UIMenu(title: "", options: .displayInline, children: debugActions),
                UIMenu(title: "", options: .displayInline, children: destructActions),
            ]
        )
        
        var menuContent: [UIMenuElement] = []
        
        if consoleTextView.text != "" {
            menuContent.append(contentsOf: [UIMenu(title: "", options: .displayInline, children: [share, resize])])
        } else {
            menuContent.append(UIMenu(title: "", options: .displayInline, children: [resize]))
        }
        
        menuContent.append(debugMenu)
        if let customMenu = menu {
            menuContent.append(customMenu)
        }
        
        if consoleTextView.text != "" {
            menuContent.append(UIMenu(title: "", options: .displayInline, children: [clear]))
        }
        
        return UIMenu(title: "", children: menuContent)
    }
    
    var consolePiPPopAnimator: UIViewPropertyAnimator?
    
    @objc func longPressAction(recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            
            guard !grabberMode else { return }
            
            feedbackGenerator.impactOccurred(intensity: 1)
            
            scrollLocked = false
            
            consolePiPPopAnimator = UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
                consoleView.transform = .init(scaleX: 1.04, y: 1.04)
            }
            consolePiPPopAnimator?.startAnimation()
            
            UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
                consoleTextView.alpha = 0.5
                menuButton.alpha = 0.5
            }.startAnimation()
        case .cancelled, .ended:
            
            if !grabberMode { scrollLocked = true }
            
            UIViewPropertyAnimator(duration: 0.8, dampingRatio: 0.6) { [self] in
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
    
    var consolePiPPanner_frameRateRequestID: UUID?
    
    @objc func consolePiPPanner(recognizer: UIPanGestureRecognizer) {
        
        if recognizer.state == .began {
            if #available(iOS 15, *) {
                consolePiPPanner_frameRateRequestID = UUID()
                FrameRateRequest.shared.activate(id: consolePiPPanner_frameRateRequestID!)
            }
            
            initialViewLocation = consoleView.center
        }
        
        guard !scrollLocked else {
            isPressed = false
            return
        }
        
        let translation = recognizer.translation(in: consoleView.superview)
        let velocity = recognizer.velocity(in: consoleView.superview)
        
        switch recognizer.state {
        case .changed:
            
            UIViewPropertyAnimator(duration: 0.175, dampingRatio: 1) { [self] in
                consoleView.center = CGPoint(x: initialViewLocation.x + translation.x,
                                             y: initialViewLocation.y + translation.y)
            }.startAnimation()
            
            reassessGrabberMode()
            
        case .ended, .cancelled:
            
            if #available(iOS 15, *), let id = consolePiPPanner_frameRateRequestID {
                consolePiPPanner_frameRateRequestID = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    FrameRateRequest.shared.deactivate(id: id)
                }
            }
            
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
            
            UserDefaults.standard.set(nearestTargetPosition.x, forKey: "LocalConsole.X")
            UserDefaults.standard.set(nearestTargetPosition.y, forKey: "LocalConsole.Y")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.reassessGrabberMode()
                self.scrollLocked = !self.grabberMode
            }
            
        default: break
        }
    }
    
    func reassessGrabberMode() {
        if consoleView.frame.maxX > 30 && consoleView.frame.minX < consoleViewController.view.frame.size.width - 30 {
            grabberMode = false
        } else {
            grabberMode = true
        }
    }
    
    var consolePiPTouchDownAnimator: UIViewPropertyAnimator?
    
    var isPressed: Bool = false {
        didSet {
            guard oldValue != isPressed else { return }
            
            if isPressed {
                guard !grabberMode else { return }
                
                consolePiPTouchDownAnimator = UIViewPropertyAnimator(duration: 0.6, dampingRatio: 1) { [self] in
                    consoleView.transform = .init(scaleX: 0.96, y: 0.96)
                }
                consolePiPTouchDownAnimator?.startAnimation(afterDelay: 0.1)
            } else {
                consolePiPTouchDownAnimator?.stopAnimation(true)
                consolePiPPopAnimator?.stopAnimation(true)
                
                UIViewPropertyAnimator(duration: scrollLocked ? 0.4 : 0.7, dampingRatio: scrollLocked ? 1 : 0.45) { [self] in
                    consoleView.transform = .identity
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
        }
    }
    
    // Simulataneously listen to all gesture recognizers.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    @objc func consolePiPTapStartEnd(recognizer: UITapStartEndGestureRecognizer) {
        switch recognizer.state {
        case .began:
            isPressed = true
        case .changed:
            break
        case .ended, .cancelled, .possible, .failed:
            isPressed = false
        @unknown default:
            break
        }
    }
}

/// Custom button that pauses console window swizzling to allow the console menu's presenting view controller to remain the top view controller.
class ConsoleMenuButton: UIButton {
    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willDisplayMenuFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
        
        SwizzleTool.pauseDidAddSubviewSwizzledClosure = true
    }
    
    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?) {
        
        SwizzleTool.pauseDidAddSubviewSwizzledClosure = false
    }
}

// Custom view that is passes touches .
class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView == self ? nil : hitView
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

class SwizzleTool: NSObject {
    
    /// Ensure context menus always show in a non reversed order.
    func swizzleContextMenuReverseOrder() {
        guard let originalMethod = class_getInstanceMethod(NSClassFromString("_" + "UI" + "Context" + "Menu" + "List" + "View").self, NSSelectorFromString("reverses" + "Action" + "Order")),
              let swizzledMethod = class_getInstanceMethod(SwizzleTool.self, #selector(swizzled_reverses_Action_Order))
        else { Swift.print("Swizzle Error Occurred"); return }
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    @objc func swizzled_reverses_Action_Order() -> Bool {
        if let menu = self.value(forKey: "displayed" + "Menu") as? UIMenu,
           menu.title == "Debug" || menu.title == "User" + "Defaults" {
            return false
        }
        
        if let orig = self.value(forKey: "_" + "reverses" + "Action" + "Order") as? Bool {
            return orig
        }
        
        return false
    }
    
    static var swizzledDidAddSubviewClosure: (() -> Void)?
    static var pauseDidAddSubviewSwizzledClosure: Bool = false
    
    func swizzleDidAddSubview(_ closure: @escaping () -> Void) {
        guard let originalMethod = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.didAddSubview(_:))),
              let swizzledMethod = class_getInstanceMethod(SwizzleTool.self, #selector(swizzled_did_add_subview(_:)))
        else { Swift.print("Swizzle Error Occurred"); return }
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
        
        Self.swizzledDidAddSubviewClosure = closure
    }

    @objc func swizzled_did_add_subview(_ subview: UIView) {
        guard !Self.pauseDidAddSubviewSwizzledClosure else { return }
        
        if let closure = Self.swizzledDidAddSubviewClosure {
            closure()
        }
    }
}

class LumaView: UIView {
    lazy var visualEffectView: UIView = {
        Bundle(path: "/Sys" + "tem/Lib" + "rary/Private" + "Framework" + "s/Material" + "Kit." + "framework")!.load()

        if let Pill = NSClassFromString("MT" + "Luma" + "Dodge" + "Pill" + "View") as? UIView.Type {
            
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
        } else {
            let visualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
            addSubview(visualEffectView)
            
            visualEffectView.translatesAutoresizingMaskIntoConstraints = false
            
            NSLayoutConstraint.activate([
                visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
                visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
                visualEffectView.topAnchor.constraint(equalTo: topAnchor),
                visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            
            return visualEffectView
        }
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
    
    // Thanks to WWDC21 UIKit Lab!
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

extension UIDevice {
    var hasNotch: Bool {
        return UIApplication.shared.windows[0].safeAreaInsets.bottom > 0
    }
}

extension String {
    func stringAfterFirstOccurenceOf(delimiter: String) -> String? {
       guard let upperIndex = (self.range(of: delimiter)?.upperBound) else { return nil }
       let trailingString: String = .init(self.suffix(from: upperIndex))
       return trailingString
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

// Support for auto-rotate.
class ConsoleViewController: UIViewController {
    var previousSize: CGSize?
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        if let previousSize = previousSize, previousSize != view.bounds.size {
            LCManager.shared.handleDeviceOrientationChange(previousSize: previousSize)
            self.previousSize = view.bounds.size
        } else if previousSize == nil {
            previousSize = view.bounds.size
        }
    }
}

// MARK: Frame Rate Request
/**
An object that allows you to manually request an increased display refresh rate on ProMotion devices.

*The display refresh rate does not exceed 60 Hz when low power mode is enabled.*

**Do not set an excessive duration. Doing so will negatively impact battery life.**
 
```
// Example
FrameRateRequest.shared.perform(duration: 0.5)
request.perform()
```
 */
@available(iOS 15, *)
final class FrameRateRequest {
    
    static let shared = FrameRateRequest()
    
    lazy private var displayLink = CADisplayLink(target: self, selector: #selector(dummyFunction))
    
    private var requestIdentifiers: [UUID] = [] {
        didSet {
            isActive = requestIdentifiers.count > 0
        }
    }
    
    private var isActive: Bool = false {
        didSet {
            guard isActive != oldValue, UIScreen.main.maximumFramesPerSecond > 60 else { return }
            
            if isActive {
                displayLink.add(to: .current, forMode: .common)
            } else {
                displayLink.invalidate()
            }
        }
    }
    
    private init() {
        guard UIScreen.main.maximumFramesPerSecond > 60 else { return }
        
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 90, maximum: Float(UIScreen.main.maximumFramesPerSecond), preferred: Float(UIScreen.main.maximumFramesPerSecond))
        
        // Ensure the DisplayLink stops when the app enters the background, or else the system will shut high frame rate capabilities until the app is suspended and relaunched.
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    /// Perform frame rate request.
    public func perform(duration: Double) {

        guard UIScreen.main.maximumFramesPerSecond > 60 else { return }
        
        let id = UUID()
        
        requestIdentifiers.append(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [self] in
            requestIdentifiers = requestIdentifiers.filter { $0 != id }
        }
    }
    
    public func activate(id: UUID) {
        requestIdentifiers.append(id)
    }
    
    public func deactivate(id: UUID) {
        requestIdentifiers = requestIdentifiers.filter { $0 != id }
    }
    
    @objc private func willEnterForeground() {
        if isActive {
            displayLink.add(to: .current, forMode: .common)
        }
    }
    
    @objc private func didEnterBackground() {
        if isActive {
            displayLink.invalidate()
        }
    }
    
    @objc private func dummyFunction() {}
}
