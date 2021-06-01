//
//  SystemReport.swift
//  LocalConsole
//
//  Created by Duraid Abdul on 2021-06-01.
//

import Foundation
import MachO

class SystemReport {
    static let shared = SystemReport()
    
    var versionString: String {
        ProcessInfo.processInfo.operatingSystemVersionString
            .replacingOccurrences(of: "Build ", with: "")
            .replacingOccurrences(of: "Version ", with: "")
    }
    
    // Current device thermal state.
    var thermalState: String {
        let state = ProcessInfo.processInfo.thermalState
        
        switch state {
        case .nominal: return "Nominal"
        case .fair : return "Fair"
        case .serious : return "Serious"
        case .critical : return "Critical"
        default: return "Unknown"
        }
    }
    
    // Retrieve device mobile gestalt cache.
    lazy var gestaltCacheExtra: NSDictionary? = {
        let url = URL(fileURLWithPath: "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist")
        
        let dictionary = NSDictionary(contentsOf: url)
        return dictionary?.value(forKey: "CacheExtra") as? NSDictionary
    }()
    
    // Device marketing name.
    lazy var gestaltMarketingName: Any = gestaltCacheExtra?.value(forKey: "Z/dqyWS6OZTRy10UcmUAhw") ?? "Unknown"
    
    // iBoot (second-stage loader) version.
    lazy var gestaltFirmwareVersion: Any = gestaltCacheExtra?.value(forKey: "LeSRsiLoJCMhjn6nd6GWbQ") ?? "Unknown"
    
    // CPU architecture.
    lazy var gestaltArchitecture: Any = gestaltCacheExtra?.value(forKey: "k7QIBwZJJOVw+Sej/8h8VA") ?? deviceArchitecture
    
    // Fallback in case gestaltArchitecture doesn't return a value.
    var deviceArchitecture: String {
        let info = NXGetLocalArchInfo()
        return String(utf8String: (info?.pointee.description)!) ?? "Unknown"
    }
    
    lazy var gestaltModelIdentifier: Any = gestaltCacheExtra?.value(forKey: "h9jDsbgj7xIVeIQ8S3/X3Q") ?? modelIdentifier
    
    // Fallback in case gestaltModelIdentifier doesn't return a value.
    var modelIdentifier: String {
        if let simulatorModelIdentifier = ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulatorModelIdentifier }
        var sysinfo = utsname()
        uname(&sysinfo) // ignore return value
        return String(bytes: Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN)), encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? "Unknown"
    }
    
    var kernel: String {
        var size = 0
        sysctlbyname("kern.ostype", nil, &size, nil, 0)
        
        var string = [CChar](repeating: 0,  count: Int(size))
        sysctlbyname("kern.ostype", &string, &size, nil, 0)
        return String(cString: string)
    }
    
    var kernelVersion: String {
        var size = 0
        sysctlbyname("kern.osrelease", nil, &size, nil, 0)
        
        var string = [CChar](repeating: 0,  count: Int(size))
        sysctlbyname("kern.osrelease", &string, &size, nil, 0)
        return String(cString: string)
    }
}
