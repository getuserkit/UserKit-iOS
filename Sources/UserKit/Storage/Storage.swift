//
//  Storage.swift
//  UserKit
//
//  Created by Peter Nicholls on 4/3/2025.
//

import Foundation
import Security

enum StorageError: Error {
    case itemNotFound
    case typeMismatch
    case encodingFailed
    case decodingFailed
    case unexpectedStatus(OSStatus)
}

final class Storage {
    private let service: String

    init() {
        self.service = "com.userkit.keychain"
    }

    // MARK: - Public API

    func set<T: Codable>(_ value: T, for key: String) throws {
        let data: Data

        if let string = value as? String {
            data = Data(string.utf8)
        } else if let dataValue = value as? Data {
            data = dataValue
        } else {
            do {
                data = try JSONEncoder().encode(value)
            } catch {
                throw StorageError.encodingFailed
            }
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)

        let attributes: [String: Any] = query.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock 
        ]) { $1 }

        let status = SecItemAdd(attributes as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw StorageError.unexpectedStatus(status)
        }
    }

    func get<T: Codable>(_ key: String, as type: T.Type) throws -> T {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status != errSecItemNotFound else {
            throw StorageError.itemNotFound
        }

        guard status == errSecSuccess else {
            throw StorageError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw StorageError.typeMismatch
        }

        if type == String.self, let string = String(data: data, encoding: .utf8) as? T {
            return string
        } else if type == Data.self, let raw = data as? T {
            return raw
        } else {
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw StorageError.decodingFailed
            }
        }
    }

    func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StorageError.unexpectedStatus(status)
        }
    }
}
