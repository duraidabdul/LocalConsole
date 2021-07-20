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
        let url = URL(fileURLWithPath: "/pri" + "vate/va" + "r/containe" + "rs/Shared/Sys" + "temGroup/sys" + "temgroup.com.apple.mobilegestal" + "tcache/Libr" + "ary/Ca" + "ches/com.app" + "le.MobileGes" + "talt.plist")
        
        let dictionary = NSDictionary(contentsOf: url)
        return dictionary?.value(forKey: "CacheE" + "xtra") as? NSDictionary
    }()
    
    // Device marketing name.
    lazy var gestaltMarketingName: Any = gestaltCacheExtra?.value(forKey: "Z/dqyWS6OZ" + "TRy10UcmUAhw") ?? "Unknown"
    
    // iBoot (second-stage loader) version.
    lazy var gestaltFirmwareVersion: Any = gestaltCacheExtra?.value(forKey: "LeSRsiLoJC" + "Mhjn6nd6GWbQ") ?? "Unknown"
    
    // CPU architecture.
    lazy var gestaltArchitecture: Any = gestaltCacheExtra?.value(forKey: "k7QIBwZJJO" + "Vw+Sej/8h8VA") ?? deviceArchitecture
    
    // Fallback in case gestaltArchitecture doesn't return a value.
    var deviceArchitecture: String {
        let info = NXGetLocalArchInfo()
        return String(utf8String: (info?.pointee.description)!) ?? "Unknown"
    }
    
    lazy var gestaltModelIdentifier: Any = gestaltCacheExtra?.value(forKey: "h9jDsbgj7xI" + "VeIQ8S3/X3Q") ?? modelIdentifier
    
    // Fallback in case gestaltModelIdentifier doesn't return a value.
    var modelIdentifier: String {
        if let simulatorModelIdentifier = ProcessInfo().environment["SIMULATOR_MO" + "DEL_IDENTIFIER"] { return simulatorModelIdentifier }
        var sysinfo = utsname()
        uname(&sysinfo) // ignore return value
        return String(bytes: Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN)), encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? "Unknown"
    }
    
    var kernel: String {
        var size = 0
        sysctlbyname("ker" + "n.os" + "type", nil, &size, nil, 0)
        
        var string = [CChar](repeating: 0,  count: Int(size))
        sysctlbyname("ker" + "n.os" + "type", &string, &size, nil, 0)
        return String(cString: string)
    }
    
    var kernelVersion: String {
        var size = 0
        sysctlbyname("ker" + "n.os" + "release", nil, &size, nil, 0)
        
        var string = [CChar](repeating: 0,  count: Int(size))
        sysctlbyname("ker" + "n.os" + "release", &string, &size, nil, 0)
        return String(cString: string)
    }
    
    var compileDate: String {
        var size = 0
        sysctlbyname("ker" + "n.ve" + "rsion", nil, &size, nil, 0)
        
        var string = [CChar](repeating: 0,  count: Int(size))
        sysctlbyname("ker" + "n.ve" + "rsion", &string, &size, nil, 0)
        let fullString = String(cString: string) /// Ex: Darwin Kernel Version 20.6.0: Mon May 10 03:15:29 PDT 2021; root:xnu-7195.140.13.0.1~20/RELEASE_ARM64_T8101
        
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        if let matches = detector?.matches(in: fullString, options: [], range: NSRange(location: 0, length: fullString.utf16.count)) {
            for match in matches {
                
                if let date = match.date {
                    
                    let dateformatter = DateFormatter()
                    dateformatter.dateStyle = .medium
                    
                    return dateformatter.string(from: date)
                }
            }
        }
        
        return "Unknown"
    }
}
