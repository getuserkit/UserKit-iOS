//
//  AppStateListener.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/10/2025.
//

import Foundation
import UIKit

@objc
protocol AppStateDelegate: AnyObject, Sendable {
    func appDidEnterBackground()
    func appWillEnterForeground()
    func appWillTerminate()
}

@MainActor
class AppStateListener {
    static let shared = AppStateListener()

    private let _queue = OperationQueue()
    let delegates = MulticastDelegate<AppStateDelegate>(label: "AppStateDelegate")

    private init() {
        let defaultCenter = NotificationCenter.default

        defaultCenter.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                  object: nil,
                                  queue: _queue)
        { _ in
            self.delegates.notify { $0.appDidEnterBackground() }
        }

        defaultCenter.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                  object: nil,
                                  queue: _queue)
        { _ in
            self.delegates.notify { $0.appWillEnterForeground() }
        }

        defaultCenter.addObserver(forName: UIApplication.willTerminateNotification,
                                  object: nil,
                                  queue: _queue)
        { _ in
            self.delegates.notify { $0.appWillTerminate() }
        }
    }
}
