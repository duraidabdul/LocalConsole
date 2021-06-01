//
//  GestureEndpointPredictor.swift
//
//  Created by Duraid Abdul.
//  Copyright © 2021 Duraid Abdul. All rights reserved.
//

import UIKit

extension CGPoint {
    
    /// Calculates the distance between two points in 2D space.
    /// + returns: The distance from this point to the given point.
    func distance(to point: CGPoint) -> CGFloat {
        // Pythagoras
        return sqrt(pow(point.x - self.x, 2) + pow(point.y - self.y, 2))
    }
}

extension UISpringTimingParameters {
    
    /**
     Simplified spring animation timing parameters.
     
     - Parameters:
     - damping: ζ (damping ratio)
     - frequency: T (frequency response)
     - initialVelocity: [See Here](https://developer.apple.com/documentation/uikit/uispringtimingparameters/1649909-initialvelocity)
     */
    convenience init(damping: CGFloat, response: CGFloat, initialVelocity: CGVector = .zero) {
        // Stiffness represents the spring constant, k
        let stiffness = pow(2 * .pi / response, 2)
        let dampingCoefficient = 4 * .pi * damping / response
        self.init(mass: 1, stiffness: stiffness, damping: dampingCoefficient, initialVelocity: initialVelocity)
    }
}

/**
 Calculates a unit vector for the initial velocity of a spring animation.
 
 - Parameters:
 - currentLocation: The current location of the view that will be animated.
 - targetLocation: The location that the view will be animated to.
 - velocity: The current velocity of the moving view. For more information, see [initialVelocity](https://developer.apple.com/documentation/uikit/uispringtimingparameters/1649909-initialvelocity).
 - Returns:
 A unit vector representing the initial velocity of the view
 
 This function can be used to form a CGVector to be used in UISpringTimingParameters.
 For more information, see [UISpringTimingParameters](https://developer.apple.com/documentation/uikit/uispringtimingparameters).
 */
func relativeVelocity(forVelocity velocity: CGFloat, from currentLocation: CGFloat, to targetLocation: CGFloat) -> CGFloat {
    let travelDistance = (targetLocation - currentLocation)
    
    // Returns an intitial velocity of 0 if
    guard travelDistance != 0 else {
        return 0
    }
    
    return velocity / travelDistance
}

/// Distance traveled after decelerating to zero velocity at a constant rate.
func project(initialVelocity: CGFloat, decelerationRate: CGFloat) -> CGFloat {
    return (initialVelocity / 1000.0) * decelerationRate / (1.0 - decelerationRate)
}

/// Calculates the nearest point from a specified array to the specified point.
func nearestTargetTo(_ point: CGPoint, possibleTargets: [CGPoint]) -> CGPoint {
    
    var currentShortestDistance = CGFloat.greatestFiniteMagnitude
    var nearestEndpoint = CGPoint.zero
    for endpoint in possibleTargets {
        let distance = point.distance(to: endpoint)
        if distance < currentShortestDistance {
            nearestEndpoint = endpoint
            currentShortestDistance = distance
        }
    }
    return nearestEndpoint
}
