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
    
    let consoleSize = CGSize(width: 212, height: 124)
    
    // Strong reference needed to keep the window alive.
    var consoleWindow: ConsoleWindow?
    
    // The console needs a view controller to display context menus.
    let viewController = UIViewController()
    lazy var consoleView = viewController.view!
    
    let consoleTextView = UITextView()
    
    var menuButton: UIButton!
    
    var scrollLocked = true
    
    let feedbackGenerator = UISelectionFeedbackGenerator()
    
    lazy var possibleEndpoints = [CGPoint(x: consoleSize.width / 2 + 12,
                                          y: UIApplication.shared.statusBarHeight + consoleSize.height / 2  + 5),
                                  CGPoint(x: UIScreen.size.width - consoleSize.width / 2 - 12,
                                          y: UIApplication.shared.statusBarHeight + consoleSize.height / 2 + 5),
                                  CGPoint(x: consoleSize.width / 2 + 12,
                                          y: UIScreen.size.height - consoleSize.height / 2 - 56),
                                  CGPoint(x: UIScreen.size.width - consoleSize.width / 2 - 12,
                                          y: UIScreen.size.height - consoleSize.height / 2 - 56)]
    
    lazy var initialViewLocation: CGPoint = .zero
    
    override init() {
        super.init()
        
        // Configure console window.
        let windowScene = UIApplication.shared
            .connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .first
        
        if let windowScene = windowScene as? UIWindowScene {
            consoleWindow = ConsoleWindow(windowScene: windowScene)
            consoleWindow?.frame = UIScreen.main.bounds
            consoleWindow?.windowLevel = UIWindow.Level.normal
            consoleWindow?.isHidden = false
            consoleWindow?.addSubview(consoleView)
            
            UIWindow.swizzleStatusBarAppearanceOverride
        }
        
        // Configure console view.
        consoleView.frame.size = consoleSize
        consoleView.backgroundColor = .black
        
        consoleView.layer.shadowRadius = 16
        consoleView.layer.shadowOpacity = 0.5
        consoleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        consoleView.center = possibleEndpoints.first!
        consoleView.alpha = 0
        
        consoleView.layer.borderWidth = 1
        consoleView.layer.borderColor = UIColor(white: 1, alpha: 0.08).cgColor
        
        consoleView.layer.cornerRadius = 19
        consoleView.layer.cornerCurve = .continuous
        
        // Configure text view.
        consoleTextView.frame = CGRect(x: 0, y: 2, width: consoleSize.width, height: consoleSize.height - 4)
        consoleTextView.isEditable = false
        consoleTextView.backgroundColor = .clear
        consoleTextView.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        
        consoleTextView.isSelectable = false
        consoleTextView.showsVerticalScrollIndicator = false
        consoleTextView.contentInsetAdjustmentBehavior = .never
        consoleView.addSubview(consoleTextView)
        
        // Configure gesture recognizers.
        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(consolePiPPanner(recognizer:)))
        panRecognizer.maximumNumberOfTouches = 1
        panRecognizer.delegate = self
        
        let tapRecognizer = UITapStartEndGestureRecognizer(target: self, action: #selector(consolePiPTapStartEnd(recognizer:)))
        tapRecognizer.delegate = self
        
        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressAction(recognizer:)))
        longPressRecognizer.minimumPressDuration = 0.1
        
        consoleView.addGestureRecognizer(panRecognizer)
        consoleView.addGestureRecognizer(tapRecognizer)
        consoleView.addGestureRecognizer(longPressRecognizer)
        
        // Prepare menu button.
        let diameter = CGFloat(25)
        
        menuButton = UIButton(frame: CGRect(x: consoleView.bounds.width - diameter - (consoleView.layer.cornerRadius - diameter / 2),
                                            y: consoleView.bounds.height - diameter - (consoleView.layer.cornerRadius - diameter / 2),
                                            width: diameter, height: diameter))
        menuButton.layer.cornerRadius = diameter / 2
        menuButton.backgroundColor = UIColor(white: 1, alpha: 0.20)
        
        let ellipsisImage = UIImageView(image: UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16)))
        ellipsisImage.frame.size = menuButton!.bounds.size
        ellipsisImage.contentMode = .center
        menuButton.addSubview(ellipsisImage)
        
        menuButton.tintColor = UIColor(white: 1, alpha: 0.75)
        menuButton.menu = makeMenu()
        menuButton.showsMenuAsPrimaryAction = true
        consoleView.addSubview(menuButton!)
        
        UIView.swizzleDebugBehaviour
    }
    
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
    
    public func print(_ items: Any) {
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = 7
        
        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 7, weight: .semibold, design: .monospaced)
        ]
        
        let string: String = {
            if consoleTextView.attributedText.string == "" {
                return "\(items)"
            } else {
                return "\(items)\n" + consoleTextView.text
            }
        }()
        
        consoleTextView.attributedText = NSAttributedString(string: string, attributes: attributes)
    }
    
    public func clear() {
        consoleTextView.text = ""
    }
    
    func makeMenu() -> UIMenu {
        let viewFrames = UIAction(title: debugBordersEnabled ? "Hide View Frames" : "Show View Frames",
                                  image: UIImage(systemName: "rectangle.3.offgrid"), handler: { _ in
                                    self.debugBordersEnabled.toggle()
                                    self.menuButton?.menu = self.makeMenu()
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
        
        return UIMenu(title: "", children: [viewFrames, respring])
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
        
        let hitView = super.hitTest(point, with: event)!
        
        return hitView.isKind(of: ConsoleWindow.self) ? nil : hitView
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
