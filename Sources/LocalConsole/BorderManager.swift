//
//  BorderManager.swift
//
//  Created by Duraid Abdul.
//  Copyright © 2021 Duraid Abdul. All rights reserved.
//

import UIKit

/// This class handles enabling and disabling debug borders on a specified view.
class BorderManager {
    weak var layer: CALayer?
    
    // Debug configuration defined.
    static let outlineWidth = 1 - 1 / UIScreen.main.scale
    let outlineColor: CGColor
    
    // Previous configuration cache.
    var cachedWidth: CGFloat?
    var cachedColor: CGColor?
    
    init(view: UIView) {
        layer = view.layer
        
        // Different colors for different UIView types.
        if "\(view.classForCoder)".contains("UIImageView") {
            outlineColor = UIColor.systemGreen.withAlphaComponent(0.85).cgColor
        } else if "\(view.classForCoder)".contains("UILabel") {
            outlineColor = UIColor.systemBlue.withAlphaComponent(0.85).cgColor
        } else if "\(view.classForCoder)".contains("UIVisualEffectView") {
            outlineColor = UIColor.systemIndigo.withAlphaComponent(0.85).cgColor
        } else {
            outlineColor = UIColor.systemYellow.withAlphaComponent(0.85).cgColor
        }
    }
    
    // Activates debug borders.
    func activate() {
        cachedWidth = layer?.borderWidth
        cachedColor = layer?.borderColor
        
        layer?.borderWidth = Self.outlineWidth
        layer?.borderColor = outlineColor
    }
    
    // Deactivates debug borders, restoring previous border properties.
    func deactivate() {
        
        guard let cachedWidth = cachedWidth, let cachedColor = cachedColor else {
            layer?.borderWidth = 0.0
            layer?.borderColor = UIColor.clear.cgColor
            return
        }
        
        // If the border width has changed since it was outlined, refrain from reverting it to the previous width.
        if layer?.borderWidth == Self.outlineWidth {
            layer?.borderWidth = cachedWidth
        }
        // If the border color has changed since it was outlined, refrain from reverting it to the previous color.
        if layer?.borderColor == outlineColor {
            layer?.borderColor = cachedColor
        }
    }
}
