//
//  Extensions.swift
//
//  Created by Duraid Abdul.
//  Copyright © 2021 Duraid Abdul. All rights reserved.
//

#if canImport(UIKit)

import UIKit

extension UIScreen {
    
    /// Screen size.
    static var size: CGSize {
        return UIScreen.main.bounds.size
    }
}

extension UIApplication {
    var statusBarHeight: CGFloat {
        if let window = UIApplication.shared.windows.first {
            return window.safeAreaInsets.top
        } else {
            return 0
        }
    }
}

extension UIFont {
    class func systemFont(ofSize size: CGFloat, weight: UIFont.Weight, design: UIFontDescriptor.SystemDesign) -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body).addingAttributes([UIFontDescriptor.AttributeName.traits : [UIFontDescriptor.TraitKey.weight : weight]]).withDesign(design)
        
        return UIFont(descriptor: descriptor!, size: size)
    }
}

#endif
