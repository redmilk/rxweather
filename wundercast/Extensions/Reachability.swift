//
//  Reachability.swift
//  Wundercast
//
//  Created by Danyl Timofeyev on 28.10.2020.
//  Copyright © 2020 Ray Wenderlich. All rights reserved.
//


import Foundation
import SystemConfiguration
import RxSwift
import RxCocoa


public let ReachabilityStatusChangedNotification = NSNotification.Name("ReachabilityStatusChangedNotification")


public enum ReachabilityType: CustomStringConvertible {
    case WWAN
    case WiFi

    public var description: String {
        switch self {
        case .WWAN: return "WWAN"
        case .WiFi: return "WiFi"
        }
    }
}

public enum ReachabilityStatus: CustomStringConvertible {
    case Offline
    case Online(ReachabilityType)
    case Unknown

    public var description: String {
        switch self {
        case .Offline: return "Offline"
        case .Online(let type): return "Online (\(type))"
        case .Unknown: return "Unknown"
        }
    }
}


final class Reachability {
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(Reachability.reachabilityCheck(_:)), name: ReachabilityStatusChangedNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    static var shared = Reachability()
    
    var connected: Observable<Bool> {
        return connectionRelay.asObservable()
    }
    
   private var connectionRelay = BehaviorRelay<Bool>(value: false)
    
    private var isConnected: Bool {
        let networkStatus = Reachability.connectionStatus()
        switch networkStatus {
        case .Unknown, .Offline:
            return false
        case .Online(.WWAN):
            return true
        case .Online(.WiFi):
            return true
        }
    }
    
    @objc fileprivate func reachabilityCheck(_ notif: NSNotification) {
           if let reachability = notif.userInfo?["Status"] as? String, reachability == "Offline" {
            connectionRelay.accept(false)
           } else {
               connectionRelay.accept(true)
           }
       }

    class func connectionStatus() -> ReachabilityStatus {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)

        guard let defaultRouteReachability = (withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }) else {
            return .Unknown
        }

        var flags: SCNetworkReachabilityFlags = []
        if !SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags) {
            return .Unknown
        }

        return ReachabilityStatus(reachabilityFlags: flags)
    }

    func monitorReachabilityChanges() {
        let host = "google.com"
        var context = SCNetworkReachabilityContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        let reachability = SCNetworkReachabilityCreateWithName(nil, host)!

        SCNetworkReachabilitySetCallback(reachability, { (_, flags, _) in
            let status = ReachabilityStatus(reachabilityFlags: flags)

            NotificationCenter.default.post(name: ReachabilityStatusChangedNotification, object: nil, userInfo: ["Status": status.description])
        }, &context)

        SCNetworkReachabilityScheduleWithRunLoop(reachability, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }
}

extension ReachabilityStatus {

    public init(reachabilityFlags flags: SCNetworkReachabilityFlags) {
        let connectionRequired = flags.contains(.connectionRequired)
        let isReachable = flags.contains(.reachable)
        let isWWAN = flags.contains(.isWWAN)

        if !connectionRequired && isReachable {
            self = .Online(isWWAN ? .WWAN : .WiFi)
        } else {
            self = .Offline
        }
    }
}
