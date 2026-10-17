//
//  VPNLocationService.swift
//  DynamicNotch
//
//  Created by Antigravity on 10/17/26.
//

import Foundation

struct VPNLocationInfo: Sendable {
    let ip: String
    let countryCode: String
}

final class VPNLocationService: Sendable {
    static let shared = VPNLocationService()
    
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 5.0
        self.session = URLSession(configuration: config)
    }
    
    func fetchCurrentLocation() async -> VPNLocationInfo? {
        // 1. Try https://api.country.is
        if let info = await fetchFromCountryIs() {
            return info
        }
        
        // 2. Try https://ipapi.co/json/
        if let info = await fetchFromIpApi() {
            return info
        }
        
        // 3. Try https://ipwho.is/
        if let info = await fetchFromIpWhoIs() {
            return info
        }
        
        return nil
    }
    
    private func fetchFromCountryIs() async -> VPNLocationInfo? {
        guard let url = URL(string: "https://api.country.is") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            struct Response: Decodable {
                let ip: String
                let country: String
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let ip = decoded.ip.trimmingCharacters(in: .whitespacesAndNewlines)
            let country = decoded.country.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ip.isEmpty, !country.isEmpty else { return nil }
            return VPNLocationInfo(ip: ip, countryCode: country)
        } catch {
            return nil
        }
    }
    
    private func fetchFromIpApi() async -> VPNLocationInfo? {
        guard let url = URL(string: "https://ipapi.co/json/") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            struct Response: Decodable {
                let ip: String?
                let country_code: String?
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard let ip = decoded.ip, !ip.isEmpty,
                  let country = decoded.country_code, !country.isEmpty else {
                return nil
            }
            return VPNLocationInfo(ip: ip, countryCode: country)
        } catch {
            return nil
        }
    }
    
    private func fetchFromIpWhoIs() async -> VPNLocationInfo? {
        guard let url = URL(string: "https://ipwho.is/") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            struct Response: Decodable {
                let ip: String?
                let country_code: String?
                let success: Bool?
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard decoded.success != false,
                  let ip = decoded.ip, !ip.isEmpty,
                  let country = decoded.country_code, !country.isEmpty else {
                return nil
            }
            return VPNLocationInfo(ip: ip, countryCode: country)
        } catch {
            return nil
        }
    }
    
    static func flag(for countryCode: String) -> String {
        let code = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 2 else { return "🌐" }
        let base: UInt32 = 127397
        var flag = ""
        for scalar in code.unicodeScalars {
            guard scalar.value >= 65 && scalar.value <= 90 else { return "🌐" }
            if let newScalar = UnicodeScalar(base + scalar.value) {
                flag.unicodeScalars.append(newScalar)
            }
        }
        return flag.isEmpty ? "🌐" : flag
    }
    
    static func inferCountryCode(from name: String) -> String? {
        let lower = name.lowercased()
        
        let countryKeywords: [(keyword: String, code: String)] = [
            ("united states", "US"), ("usa", "US"),
            ("germany", "DE"), ("deutschland", "DE"),
            ("united kingdom", "GB"), ("great britain", "GB"), ("england", "GB"),
            ("netherlands", "NL"), ("holland", "NL"),
            ("france", "FR"),
            ("canada", "CA"),
            ("singapore", "SG"),
            ("japan", "JP"),
            ("switzerland", "CH"),
            ("sweden", "SE"),
            ("poland", "PL"),
            ("turkey", "TR"), ("türkiye", "TR"),
            ("ukraine", "UA"),
            ("spain", "ES"),
            ("italy", "IT"),
            ("finland", "FI"),
            ("norway", "NO"),
            ("brazil", "BR"),
            ("india", "IN"),
            ("korea", "KR"),
            ("hong kong", "HK"),
            ("taiwan", "TW"),
            ("australia", "AU"),
            ("austria", "AT"),
            ("belgium", "BE"),
            ("ireland", "IE"),
            ("czech", "CZ"),
            ("romania", "RO"),
            ("israel", "IL"),
            ("uae", "AE"), ("dubai", "AE"),
            ("russia", "RU")
        ]
        
        for item in countryKeywords {
            if lower.contains(item.keyword) {
                return item.code
            }
        }
        
        let tokens = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
        for token in tokens {
            if token.count == 2 && token == token.uppercased() {
                let scalar1 = token.unicodeScalars.first!.value
                let scalar2 = token.unicodeScalars.dropFirst().first!.value
                if scalar1 >= 65 && scalar1 <= 90 && scalar2 >= 65 && scalar2 <= 90 {
                    let exclusions: Set<String> = ["IP", "UI", "OS", "ID", "OK", "MY", "TO", "ON", "IN", "AT", "NO", "GO"]
                    if !exclusions.contains(token) {
                        return token
                    }
                }
            }
        }
        return nil
    }
}
