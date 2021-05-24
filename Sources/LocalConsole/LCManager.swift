//
//  LocalConsole.swift
//
//  Created by Duraid Abdul.
//  Copyright © 2021 Duraid Abdul. All rights reserved.
//

#if canImport(UIKit)

import UIKit

var GLOBAL_DEBUG_BORDERS = false
var GLOBAL_BORDER_TRACKERS: [BorderManager] = []

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
    
    let defaultConsoleSize = CGSize(width: 212, height: 124)
    
    /// The fixed size of the console view.
    lazy var consoleSize = defaultConsoleSize {
        didSet {
            consoleView.frame.size = consoleSize
            if consoleView.frame.size.width > ResizeController.kMaxConsoleWidth {
                consoleTextView.frame.size.width = ResizeController.kMaxConsoleWidth
            } else {
                consoleTextView.frame.size.width = consoleSize.width
            }
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
    let consoleTextView = UITextView()
    
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
                            y: UIScreen.portraitSize.height - consoleSize.height / 2 - (consoleWindow?.safeAreaInsets.bottom ?? 0) - 12),
                    CGPoint(x: UIScreen.portraitSize.width - consoleSize.width / 2 - 12,
                            y: UIScreen.portraitSize.height - consoleSize.height / 2 - (consoleWindow?.safeAreaInsets.bottom ?? 0) - 12)]
        } else {
            return [CGPoint(x: UIScreen.portraitSize.width / 2,
                            y: (UIScreen.hasRoundedCorners ? 44 : 16) + consoleSize.height / 2 + 12),
                    CGPoint(x: UIScreen.portraitSize.width / 2,
                            y: UIScreen.portraitSize.height - consoleSize.height / 2 - (consoleWindow?.safeAreaInsets.bottom ?? 0) - 12)]
        }
    }
    
    lazy var initialViewLocation: CGPoint = .zero
    
    override init() {
        super.init()
        
        configureWindow()
        
        consoleSize = CGSize(width: UserDefaults.standard.object(forKey: "LocalConsole_Width") as? CGFloat ?? consoleSize.width,
                             height: UserDefaults.standard.object(forKey: "LocalConsole_Height") as? CGFloat ?? consoleSize.height)
        
        consoleView.backgroundColor = .black
        
        consoleView.layer.shadowRadius = 16
        consoleView.layer.shadowOpacity = 0.5
        consoleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        consoleView.center = possibleEndpoints.first!
        consoleView.alpha = 0
        
        consoleView.layer.cornerRadius = 20
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
        consoleTextView.frame = CGRect(x: 0, y: 2, width: consoleSize.width, height: consoleSize.height - 4)
        consoleTextView.isEditable = false
        consoleTextView.backgroundColor = .clear
        consoleTextView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        
        consoleTextView.isSelectable = false
        consoleTextView.showsVerticalScrollIndicator = false
        consoleTextView.contentInsetAdjustmentBehavior = .never
        consoleTextView.autoresizingMask = [.flexibleHeight]
        consoleView.addSubview(consoleTextView)
        
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
        let diameter = CGFloat(26)
        
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
        
        let ellipsisImage = UIImageView(image: UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16)))
        ellipsisImage.frame.size = circle.bounds.size
        ellipsisImage.contentMode = .center
        circle.addSubview(ellipsisImage)
        
        menuButton.tintColor = UIColor(white: 1, alpha: 0.75)
        menuButton.menu = makeMenu()
        menuButton.showsMenuAsPrimaryAction = true
        consoleView.addSubview(menuButton)
        
        UIView.swizzleDebugBehaviour
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
                consoleView.transform = .init(scaleX: 0.9, y: 0.9)
                UIViewPropertyAnimator(duration: 0.5, dampingRatio: 0.6) { [self] in
                    consoleView.transform = .init(scaleX: 1, y: 1)
                }.startAnimation()
                UIViewPropertyAnimator(duration: 0.3, dampingRatio: 1) { [self] in
                    consoleView.alpha = 1
                }.startAnimation()
            } else {
                UIViewPropertyAnimator(duration: 0.25, dampingRatio: 1) { [self] in
                    consoleView.transform = .init(scaleX: 0.9, y: 0.9)
                    consoleView.alpha = 0
                }.startAnimation()
            }
        }
    }
    
    /// Print items to the console view.
    public func print(_ items: Any) {
        let string: String = {
            if consoleTextView.text == "" {
                return "\(items)"
            } else {
                return "\(items)\n" + consoleTextView.text
            }
        }()
        
        setAttributedText(string)
        
        // Update the context menu to show the clipboard/clear actions.
        menuButton.menu = makeMenu()
    }
    
    /// Clear text in the console view.
    public func clear() {
        consoleTextView.text = ""
        
        // Update the context menu to hide the clipboard/clear actions.
        menuButton.menu = makeMenu()
    }
    
    /// Copy the console view text to the device's clipboard.
    public func copy() {
        UIPasteboard.general.string = consoleTextView.text
    }
    
    // MARK: - Private
    
    private var debugBordersEnabled = false {
        didSet {
            GLOBAL_DEBUG_BORDERS = debugBordersEnabled
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
    
    @objc func toggleLock() {
        scrollLocked.toggle()
    }
    
    func toggleVisibility() {
        if isVisible {
            UIViewPropertyAnimator(duration: 0.25, dampingRatio: 1) { [self] in
                consoleView.transform = .init(scaleX: 0.9, y: 0.9)
                consoleView.alpha = 0
            }.startAnimation()
            
            isVisible = false
        } else {
            UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
                consoleView.transform = .init(scaleX: 1, y: 1)
                consoleView.alpha = 1
            }.startAnimation()
            
            isVisible = true
        }
        
        // Renders color properly (for dark appearance).
        consoleView.backgroundColor = .black
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
        
        let viewFrames = UIAction(title: debugBordersEnabled ? "Hide View Frames" : "Show View Frames",
                                  image: UIImage(systemName: "rectangle.3.offgrid"), handler: { _ in
                                    self.debugBordersEnabled.toggle()
                                    self.menuButton.menu = self.makeMenu()
                                  })
        
        let respring = UIAction(title: "Restart SpringBoard",
                                image: UIImage(systemName: "apps.iphone"), handler: { _ in
                                    guard let window = UIApplication.shared.windows.first else { return }
                                    
                                    window.layer.cornerRadius = UIScreen.main.value(forKey: "_displayCornerRadius") as! CGFloat
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
        let debugActions = UIMenu(title: "", options: .displayInline, children: [viewFrames, respring])
        
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
    static let swizzleDebugBehaviour: Void = {
        guard let originalMethod = class_getInstanceMethod(UIView.self, #selector(layoutSubviews)),
              let swizzledMethod = class_getInstanceMethod(UIView.self, #selector(swizzled_layoutSubviews)) else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    @objc func swizzled_layoutSubviews() {
        swizzled_layoutSubviews()
        
        if GLOBAL_DEBUG_BORDERS {
            let tracker = BorderManager(view: self)
            GLOBAL_BORDER_TRACKERS.append(tracker)
            tracker.activate()
        }
    }
}

extension UIWindow {
    
    /// Make sure this window does not have control over the status bar appearance.
    static let swizzleStatusBarAppearanceOverride: Void = {
        guard let originalMethod = class_getInstanceMethod(UIWindow.self, NSSelectorFromString("_can" + "Affect" + "Status" + "Bar" + "Appearance")),
              let swizzledMethod = class_getInstanceMethod(UIWindow.self, #selector(swizzled_statusBarAppearance))
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()
    
    @objc func swizzled_statusBarAppearance() -> Bool {
        return isKeyWindow
    }
}

#endif
