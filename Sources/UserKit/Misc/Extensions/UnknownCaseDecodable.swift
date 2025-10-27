//
//  UnknownCaseDecodable.swift
//  UserKit
//
//  Created by Peter Nicholls on 5/8/2025.
//

import Foundation

public protocol UnknownCaseDecodable: Decodable where Self: RawRepresentable {
    static var unknown: Self { get }
}

public extension UnknownCaseDecodable where RawValue: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(RawValue.self)
        self = .init(rawValue: rawValue) ?? Self.unknown
    }
}
