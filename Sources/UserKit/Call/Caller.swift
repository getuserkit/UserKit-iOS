//
//  Caller.swift
//  UserKit
//
//  Created by Peter Nicholls on 9/9/2025.
//

struct Caller: Codable {
    let id: String
    let firstName: String
    let lastName: String
    
    var name: String {
        [firstName, lastName].joined(separator: " ")
    }
}
