//
//  ResizeController.swift
//
//  Created by Duraid Abdul.
//  Copyright © 2021 Duraid Abdul. All rights reserved.
//

import UIKit

@available(iOSApplicationExtension, unavailable)
class ResizeController {
    
    public static let shared = ResizeController()
    
    lazy var platterView = PlatterView(frame: .zero)
    
    var consoleCenterPoint: CGPoint {
        let containerViewSize = LCManager.shared.consoleViewController.view.frame.size
        
        return CGPoint(x: (containerViewSize.width * UIScreen.main.scale / 2).rounded() / UIScreen.main.scale,
                       y: (containerViewSize.height * UIScreen.main.scale / 2).rounded() / UIScreen.main.scale
                         + (UIScreen.hasRoundedCorners ? 0 : 24))
    }
    
    lazy var consoleOutlineView: UIView = {
        
        let consoleViewReference = LCManager.shared.consoleView
        
        let view = UIView()
        view.layer.borderWidth = 2
        view.layer.borderColor = UIColor.systemGreen.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).cgColor
        view.layer.cornerRadius = consoleViewReference.layer.cornerRadius + 6
        view.layer.cornerCurve = .continuous
        view.alpha = 0
        
        consoleViewReference.addSubview(view)
        
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: consoleViewReference.leadingAnchor, constant: -6),
            view.trailingAnchor.constraint(equalTo: consoleViewReference.trailingAnchor, constant: 6),
            view.topAnchor.constraint(equalTo: consoleViewReference.topAnchor, constant: -6),
            view.bottomAnchor.constraint(equalTo: consoleViewReference.bottomAnchor, constant: 6)
        ])
        
        return view
    }()
    
    lazy var bottomGrabberPillView = UIView()
    
    lazy var bottomGrabber: UIView = {
        let view = UIView()
        LCManager.shared.consoleViewController.view.addSubview(view)
        
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 116),
            view.heightAnchor.constraint(equalToConstant: 46),
            view.centerXAnchor.constraint(equalTo: consoleOutlineView.centerXAnchor),
            view.topAnchor.constraint(equalTo: consoleOutlineView.bottomAnchor, constant: -18)
        ])
        
        bottomGrabberPillView.frame = CGRect(x: 58 - 18, y: 25, width: 36, height: 5)
        bottomGrabberPillView.backgroundColor = UIColor.label
        bottomGrabberPillView.alpha = 0.3
        bottomGrabberPillView.layer.cornerRadius = 2.5
        bottomGrabberPillView.layer.cornerCurve = .continuous
        view.addSubview(bottomGrabberPillView)
        
        let verticalPanGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(verticalPanner(recognizer:)))
        verticalPanGestureRecognizer.maximumNumberOfTouches = 1
        view.addGestureRecognizer(verticalPanGestureRecognizer)
        
        view.alpha = 0
        
        return view
    }()
    
    lazy var rightGrabberPillView = UIView()
    
    lazy var rightGrabber: UIView = {
        let view = UIView()
        LCManager.shared.consoleViewController.view.addSubview(view)
        
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 46),
            view.heightAnchor.constraint(equalToConstant: 116),
            view.centerYAnchor.constraint(equalTo: consoleOutlineView.centerYAnchor),
            view.leftAnchor.constraint(equalTo: consoleOutlineView.rightAnchor, constant: -18)
        ])
        
        rightGrabberPillView.frame = CGRect(x: 25, y: 58 - 18, width: 5, height: 36)
        rightGrabberPillView.backgroundColor = UIColor.label
        rightGrabberPillView.alpha = 0.3
        rightGrabberPillView.layer.cornerRadius = 2.5
        rightGrabberPillView.layer.cornerCurve = .continuous
        view.addSubview(rightGrabberPillView)
        
        let horizontalPanGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(horizontalPanner(recognizer:)))
        horizontalPanGestureRecognizer.maximumNumberOfTouches = 1
        view.addGestureRecognizer(horizontalPanGestureRecognizer)
        
        view.alpha = 0
        
        return view
    }()
    
    var isActive: Bool = false {
        didSet {
            guard isActive != oldValue else { return }
            
            // Initialize views outside of animation.
            _ = platterView
            _ = consoleOutlineView
            _ = bottomGrabber
            _ = rightGrabber
            
            // Ensure initial autolayout is performed unanimated.
            LCManager.shared.consoleViewController.view.layoutIfNeeded()
            
            if #available(iOS 15, *) {
                FrameRateRequest.shared.perform(duration: 1.5)
            }
            
            if isActive {
                
                UIViewPropertyAnimator(duration: 0.75, dampingRatio: 1) {
                    
                    let textView = LCManager.shared.consoleTextView
                    
                    textView.contentOffset.y = textView.contentSize.height - textView.bounds.size.height
                }.startAnimation()
                
                
                if LCManager.shared.consoleView.traitCollection.userInterfaceStyle == .light {
                    LCManager.shared.consoleView.layer.shadowOpacity = 0.25
                }
                
                // Ensure background color animates in right the first time.
                LCManager.shared.consoleViewController.view.backgroundColor = .clear
                
                UIViewPropertyAnimator(duration: 0.6, dampingRatio: 1) {
                    LCManager.shared.consoleView.center = self.consoleCenterPoint
                    
                    // Update grabbers (layout constraints)
                    LCManager.shared.consoleViewController.view.layoutIfNeeded()
                    
                    LCManager.shared.menuButton.alpha = 0
                    
                    LCManager.shared.consoleViewController.view.backgroundColor = UIColor(dynamicProvider: { traitCollection in
                        UIColor(white: 0, alpha: traitCollection.userInterfaceStyle == .light ? 0.1 : 0.3)
                    })
                }.startAnimation()
                
                UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
                    consoleOutlineView.alpha = 1
                }.startAnimation(afterDelay: 0.3)
                
                bottomGrabber.transform = .init(translationX: 0, y: -5)
                rightGrabber.transform = .init(translationX: -5, y: 0)
                
                UIViewPropertyAnimator(duration: 1, dampingRatio: 1) { [self] in
                    bottomGrabber.alpha = 1
                    rightGrabber.alpha = 1
                    
                    bottomGrabber.transform = .identity
                    rightGrabber.transform = .identity
                }.startAnimation(afterDelay: 0.3)
                
                LCManager.shared.panRecognizer.isEnabled = false
                LCManager.shared.longPressRecognizer.isEnabled = false
                
                // Activate full screen button.
                consoleOutlineView.isUserInteractionEnabled = true
            } else {
                
                LCManager.shared.consoleView.layer.shadowOpacity = 0.5
                
                UIViewPropertyAnimator(duration: 0.6, dampingRatio: 1) {
                    LCManager.shared.snapToCachedEndpoint()
                    
                    // Update grabbers (layout constraints)
                    LCManager.shared.consoleViewController.view.layoutIfNeeded()
                    
                    LCManager.shared.menuButton.alpha = 1
                    
                    LCManager.shared.consoleViewController.view.backgroundColor = .clear
                }.startAnimation()
                
                UIViewPropertyAnimator(duration: 0.2, dampingRatio: 1) { [self] in
                    consoleOutlineView.alpha = 0
                    
                    bottomGrabber.alpha = 0
                    rightGrabber.alpha = 0
                }.startAnimation()
                
                LCManager.shared.panRecognizer.isEnabled = true
                LCManager.shared.longPressRecognizer.isEnabled = true
                
                // Deactivate full screen button.
                consoleOutlineView.isUserInteractionEnabled = false
            }
        }
    }
    
    var initialHeight = CGFloat.zero
    
    static let kMinConsoleHeight: CGFloat = 108
    static let kMaxConsoleHeight: CGFloat = 346
    
    var verticalPanner_frameRateRequestID: UUID?
    
    @objc func verticalPanner(recognizer: UIPanGestureRecognizer) {
        
        let translation = recognizer.translation(in: bottomGrabber.superview)
        
        let minHeight = Self.kMinConsoleHeight
        let maxHeight = Self.kMaxConsoleHeight
        
        switch recognizer.state {
        case .began:
            if #available(iOS 15, *) {
                verticalPanner_frameRateRequestID = UUID()
                FrameRateRequest.shared.activate(id: verticalPanner_frameRateRequestID!)
            }
            
            initialHeight = LCManager.shared.consoleSize.height
            
            UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
                bottomGrabberPillView.alpha = 0.6
            }.startAnimation()
            
        case .changed:
            
            let resolvedHeight: CGFloat = {
                let initialEstimate = initialHeight + 2 * translation.y
                if initialEstimate <= maxHeight && initialEstimate > minHeight {
                    return initialEstimate
                } else if initialEstimate > maxHeight {
                    
                    var excess = initialEstimate - maxHeight
                    excess = 25 * log(1/25 * excess + 1)
                    
                    return maxHeight + excess
                } else {
                    var excess = minHeight - initialEstimate
                    excess = 7 * log(1/7 * excess + 1)
                    
                    return minHeight - excess
                }
            }()
            
            LCManager.shared.lumaHeightAnchor.constant = resolvedHeight
            LCManager.shared.consoleSize.height = resolvedHeight
            LCManager.shared.consoleView.center.y = consoleCenterPoint.y
            
        case .ended, .cancelled:
           
            if #available(iOS 15, *), let id = verticalPanner_frameRateRequestID {
                verticalPanner_frameRateRequestID = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    FrameRateRequest.shared.deactivate(id: id)
                }
            }
            
            UIViewPropertyAnimator(duration: 0.4, dampingRatio: 0.7) {
                if LCManager.shared.consoleSize.height > maxHeight {
                    LCManager.shared.consoleSize.height = maxHeight
                    LCManager.shared.lumaHeightAnchor.constant = maxHeight
                }
                if LCManager.shared.consoleSize.height < minHeight {
                    LCManager.shared.consoleSize.height = minHeight
                    LCManager.shared.lumaHeightAnchor.constant = minHeight
                }
                
                LCManager.shared.consoleView.center.y = self.consoleCenterPoint.y
                
                // Animate autolayout updates.
                LCManager.shared.consoleViewController.view.layoutIfNeeded()
            }.startAnimation()
            
            UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
                bottomGrabberPillView.alpha = 0.3
            }.startAnimation()
            
        default: break
        }
    }
    
    var initialWidth = CGFloat.zero
    
    static let kMinConsoleWidth: CGFloat = 112
    static let kMaxConsoleWidth: CGFloat = [UIScreen.portraitSize.width, UIScreen.portraitSize.height].min()! - 56
    
    var horizontalPanner_frameRateRequestID: UUID?
    
    @objc func horizontalPanner(recognizer: UIPanGestureRecognizer) {
        
        let translation = recognizer.translation(in: bottomGrabber.superview)
        
        let minWidth = Self.kMinConsoleWidth
        let maxWidth = Self.kMaxConsoleWidth
        
        switch recognizer.state {
        case .began:
            if #available(iOS 15, *) {
                horizontalPanner_frameRateRequestID = UUID()
                FrameRateRequest.shared.activate(id: horizontalPanner_frameRateRequestID!)
            }
            
            initialWidth = LCManager.shared.consoleSize.width
            
            UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
                rightGrabberPillView.alpha = 0.6
            }.startAnimation()
            
        case .changed:
            
            let resolvedWidth: CGFloat = {
                let initialEstimate = initialWidth + 2 * translation.x
                if initialEstimate <= maxWidth && initialEstimate > minWidth {
                    return initialEstimate
                } else if initialEstimate > maxWidth {
                    
                    var excess = initialEstimate - maxWidth
                    excess = 25 * log(1/25 * excess + 1)
                    
                    return maxWidth + excess
                } else {
                    var excess = minWidth - initialEstimate
                    excess = 7 * log(1/7 * excess + 1)
                    
                    return minWidth - excess
                }
            }()
            
            LCManager.shared.consoleSize.width = resolvedWidth
            LCManager.shared.consoleView.center.x = (UIScreen.main.nativeBounds.width * 1/2).rounded() / UIScreen.main.scale
            
        case .ended, .cancelled:
            
            if #available(iOS 15, *), let id = horizontalPanner_frameRateRequestID {
                horizontalPanner_frameRateRequestID = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    FrameRateRequest.shared.deactivate(id: id)
                }
            }
            
            UIViewPropertyAnimator(duration: 0.4, dampingRatio: 0.7) {
                if LCManager.shared.consoleSize.width > maxWidth {
                    LCManager.shared.consoleSize.width = maxWidth
                }
                if LCManager.shared.consoleSize.width < minWidth {
                    LCManager.shared.consoleSize.width = minWidth
                }
                
                LCManager.shared.consoleView.center.x = (UIScreen.main.nativeBounds.width * 1/2).rounded() / UIScreen.main.scale
                
                // Animate autolayout updates.
                LCManager.shared.consoleViewController.view.layoutIfNeeded()
            }.startAnimation()
            
            UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) { [self] in
                rightGrabberPillView.alpha = 0.3
            }.startAnimation()
            
        default: break
        }
    }
}

@available(iOSApplicationExtension, unavailable)
class PlatterView: UIView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.shadowRadius = 10
        layer.shadowOpacity = 0.125
        layer.shadowOffset = CGSize(width: 0, height: 0)
        
        layer.borderColor = dynamicBorderColor.cgColor
        layer.borderWidth = 1 / UIScreen.main.scale
        layer.cornerRadius = 30
        layer.cornerCurve = .continuous
        
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        
        blurView.layer.cornerRadius = 30
        blurView.layer.cornerCurve = .continuous
        blurView.clipsToBounds = true
        
        blurView.frame = bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        addSubview(blurView)
        
        LCManager.shared.consoleViewController.view.addSubview(self)
        LCManager.shared.consoleViewController.view.sendSubviewToBack(self)
        
        _ = backgroundButton
        
        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(platterPanner(recognizer:)))
        panRecognizer.maximumNumberOfTouches = 1
        addGestureRecognizer(panRecognizer)
        
        let grabber = UIView()
        grabber.frame.size = CGSize(width: 36, height: 5)
        grabber.frame.origin.y = 10
        grabber.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
        grabber.backgroundColor = .label
        grabber.alpha = 0.1
        grabber.layer.cornerRadius = 2.5
        grabber.layer.cornerCurve = .continuous
        addSubview(grabber)
        
        let titleLabel = UILabel()
        titleLabel.text = "Resize Console"
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.sizeToFit()
        titleLabel.frame.origin.y = 28
        titleLabel.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
        addSubview(titleLabel)
        
        let subtitleLabel = UILabel()
        subtitleLabel.text = "Use the grabbers to resize the console."
        subtitleLabel.font = .systemFont(ofSize: 17, weight: .medium)
        subtitleLabel.sizeToFit()
        subtitleLabel.alpha = 0.5
        subtitleLabel.frame.origin.y = titleLabel.frame.maxY + 8
        subtitleLabel.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
        addSubview(subtitleLabel)
        
        let buttonContainerView = UIView()
        buttonContainerView.addSubview(resetButton)
        buttonContainerView.addSubview(doneButton)
        addSubview(buttonContainerView)
        
        buttonContainerView.translatesAutoresizingMaskIntoConstraints = false
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            
            buttonContainerView.widthAnchor.constraint(equalToConstant: 264),
            buttonContainerView.heightAnchor.constraint(equalToConstant: 52),
            buttonContainerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttonContainerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -possibleEndpoints[0].y * 2),
            
            resetButton.widthAnchor.constraint(equalToConstant: 116),
            resetButton.heightAnchor.constraint(equalToConstant: 52),
            resetButton.leadingAnchor.constraint(equalTo: buttonContainerView.leadingAnchor),
            resetButton.topAnchor.constraint(equalTo: buttonContainerView.topAnchor),
            
            doneButton.widthAnchor.constraint(equalToConstant: 116),
            doneButton.heightAnchor.constraint(equalToConstant: 52),
            doneButton.trailingAnchor.constraint(equalTo: buttonContainerView.trailingAnchor),
            doneButton.topAnchor.constraint(equalTo: buttonContainerView.topAnchor)
        ])
    }
    
    lazy var backgroundButton: UIButton = {
        let backgroundButton = UIButton(primaryAction: UIAction(handler: { _ in
            ResizeController.shared.isActive = false
            self.dismiss()
        }))
        backgroundButton.frame.size = CGSize(width: self.frame.size.width, height: possibleEndpoints[0].y + 30)
        LCManager.shared.consoleViewController.view.addSubview(backgroundButton)
        LCManager.shared.consoleViewController.view.sendSubviewToBack(backgroundButton)
        return backgroundButton
    }()
    
    lazy var doneButton: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = UIColor.systemBlue.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        button.setTitle("Done", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        button.layer.cornerRadius = 20
        button.layer.cornerCurve = .continuous
        
        button.addAction(UIAction(handler: { _ in
            ResizeController.shared.isActive = false
            self.dismiss()
        }), for: .touchUpInside)
        
        button.addActions(highlightAction: UIAction(handler: { _ in
            UIViewPropertyAnimator(duration: 0.25, dampingRatio: 1) {
                button.alpha = 0.6
            }.startAnimation()
        }), unhighlightAction: UIAction(handler: { _ in
            UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) {
                button.alpha = 1
            }.startAnimation()
        }))
        
        return button
    }()
    
    lazy var resetButton: UIButton = {
        let button = UIButton(type: .custom)
        button.backgroundColor = UIColor(dynamicProvider: { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(white: 1, alpha: 0.125)
            } else {
                return UIColor(white: 0, alpha: 0.1)
            }
        })
        
        button.setTitle("Reset", for: .normal)
        button.setTitleColor(.label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        button.layer.cornerRadius = 20
        button.layer.cornerCurve = .continuous
        
        button.addAction(UIAction(handler: { _ in
            
            // Resolves a text view frame animation bug that occurs when *decreasing* text view width.
            if LCManager.shared.consoleSize.width > LCManager.shared.defaultConsoleSize.width {
                LCManager.shared.consoleTextView.frame.size.width = LCManager.shared.defaultConsoleSize.width - 4
            }
            
            UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) {
                LCManager.shared.consoleSize = LCManager.shared.defaultConsoleSize
                LCManager.shared.lumaHeightAnchor.constant = LCManager.shared.defaultConsoleSize.height
                LCManager.shared.consoleView.center = ResizeController.shared.consoleCenterPoint
                LCManager.shared.consoleViewController.view.layoutIfNeeded()
            }.startAnimation()
            
        }), for: .touchUpInside)
        
        button.addActions(highlightAction: UIAction(handler: { _ in
            UIViewPropertyAnimator(duration: 0.25, dampingRatio: 1) {
                button.alpha = 0.6
            }.startAnimation()
        }), unhighlightAction: UIAction(handler: { _ in
            UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) {
                button.alpha = 1
            }.startAnimation()
        }))
        
        return button
    }()
    
    func configureFrame() {
        self.frame.size = LCManager.shared.consoleViewController.view.frame.size
        // Make sure bottom doesn't show on upwards pan.
        self.frame.size.height += 50
        self.frame.origin = possibleEndpoints[1]
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    
    func reveal() {
        
        configureFrame()
        
        UIViewPropertyAnimator(duration: 0.6, dampingRatio: 1) {
            self.frame.origin = self.possibleEndpoints[0]
        }.startAnimation()
        
        backgroundButton.isHidden = false
        
        isHidden = false
    }
    
    func dismiss() {
        let animator = UIViewPropertyAnimator(duration: 0.6, dampingRatio: 1) {
            self.frame.origin = self.possibleEndpoints[1]
        }
        animator.addCompletion { _ in
            self.isHidden = true
        }
        animator.startAnimation()
        
        backgroundButton.isHidden = true
    }
    
    let dynamicBorderColor = UIColor(dynamicProvider: { traitCollection in
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor(white: 1, alpha: 0.075)
        } else {
            return UIColor(white: 0, alpha: 0.125)
        }
    })
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        layer.borderColor = dynamicBorderColor.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var possibleEndpoints: [CGPoint] { return [CGPoint(x: 0, y: (UIScreen.hasRoundedCorners ? 44 : -8) + 63),
                                               CGPoint(x: 0, y: LCManager.shared.consoleViewController.view.frame.size.height + 5)]
    }
    
    var initialPlatterOriginY = CGFloat.zero
    
    @objc func platterPanner(recognizer: UIPanGestureRecognizer) {
        
        let translation = recognizer.translation(in: superview)
        let velocity = recognizer.velocity(in: superview)
        
        switch recognizer.state {
        case .began:
            initialPlatterOriginY = frame.origin.y
        case .changed:
            
            let resolvedOriginY: CGFloat = {
                let initialEstimate = initialPlatterOriginY + translation.y
                if initialEstimate >= possibleEndpoints[0].y {
                    
                    // Stick buttons to bottom.
                    [doneButton, resetButton,
                     ResizeController.shared.bottomGrabber, ResizeController.shared.rightGrabber,
                     LCManager.shared.consoleView
                    ].forEach {
                        $0.transform = .identity
                    }
                    
                    return initialEstimate
                } else {
                    var excess = possibleEndpoints[0].y - initialEstimate
                    excess = 10 * log(1/10 * excess + 1)
                    
                    // Stick buttons to bottom.
                    doneButton.transform = .init(translationX: 0, y: excess)
                    resetButton.transform = .init(translationX: 0, y: excess)
                    
                    ResizeController.shared.bottomGrabber.transform = .init(translationX: 0, y: -excess / 2.5)
                    ResizeController.shared.rightGrabber.transform = .init(translationX: 0, y: -excess / 2)
                    LCManager.shared.consoleView.transform = .init(translationX: 0, y: -excess / 2)
                    
                    return possibleEndpoints[0].y - excess
                }
            }()
            
            if frame.origin.y > possibleEndpoints[0].y + 40 {
                ResizeController.shared.isActive = false
            } else {
                ResizeController.shared.isActive = true
            }
            
            frame.origin.y = resolvedOriginY
            
        case .ended, .cancelled:
            
            // After the PiP is thrown, determine the best corner and re-target it there.
            let decelerationRate = UIScrollView.DecelerationRate.normal.rawValue
            
            let projectedPosition = CGPoint(
                x: 0,
                y: frame.origin.y + project(initialVelocity: velocity.y, decelerationRate: decelerationRate)
            )
            
            let nearestTargetPosition = nearestTargetTo(projectedPosition, possibleTargets: possibleEndpoints)
            
            let relativeInitialVelocity = CGVector(
                dx: 0,
                dy: frame.origin.y >= possibleEndpoints[0].y
                    ? relativeVelocity(forVelocity: velocity.y, from: frame.origin.y, to: nearestTargetPosition.y)
                    : 0
            )
            
            let timingParameters = UISpringTimingParameters(damping: 1, response: 0.4, initialVelocity: relativeInitialVelocity)
            let positionAnimator = UIViewPropertyAnimator(duration: 0, timingParameters: timingParameters)
            positionAnimator.addAnimations { [self] in
                frame.origin = nearestTargetPosition
                
                [doneButton, resetButton,
                 ResizeController.shared.bottomGrabber, ResizeController.shared.rightGrabber,
                 LCManager.shared.consoleView
                ].forEach {
                    $0.transform = .identity
                }
            }
            
            if nearestTargetPosition == possibleEndpoints[1] {
                ResizeController.shared.isActive = false
                backgroundButton.isHidden = true
                
                positionAnimator.addCompletion { _ in
                    self.isHidden = true
                }
            } else {
                ResizeController.shared.isActive = true
            }
            
            positionAnimator.startAnimation()
            
        default: break
        }
    }
}
