import Foundation

enum PersonType: String, Codable, CaseIterable, Identifiable {
    case homeless
    case volunteer
    case employee
    case admin

    var id: String { rawValue }

    var label: String {
        switch self {
        case .homeless: return "Person we serve"
        case .volunteer: return "Volunteer"
        case .employee: return "Employee"
        case .admin: return "Admin"
        }
    }

    var isStaff: Bool { self != .homeless }
}

enum Gender: String, Codable, CaseIterable, Identifiable {
    case female
    case male
    case nonbinary
    case other
    case preferNotToSay = "prefer_not_to_say"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .nonbinary: return "Non-binary"
        case .other: return "Other"
        case .preferNotToSay: return "Prefer not to say"
        }
    }
}

struct User: Codable, Identifiable {
    let id: String
    let personType: String
    let name: String
    let email: String?
    let gender: String?
    let phone: String?
    let isStaff: Bool
}

struct RegisterRequest: Encodable {
    let name: String
    let email: String?
    let gender: String?
    let phone: String?
    let personType: String
    let staffCode: String?
}

struct RegisterResponse: Codable {
    let user: User
    let token: String
    let message: String?
}

struct MeResponse: Codable {
    let user: User
}

struct DeleteResponse: Codable {
    let deleted: Bool
}

struct DisclosureResponse: Codable {
    let version: String
    let text: String
}

struct ConsentStatus: Codable {
    let granted: Bool
    let consentVersion: String?
    let grantedAt: String?
    let revokedAt: String?
    let lastRecordedAt: String?

    enum CodingKeys: String, CodingKey {
        case granted
        case consentVersion = "consent_version"
        case grantedAt = "granted_at"
        case revokedAt = "revoked_at"
        case lastRecordedAt = "last_recorded_at"
    }
}

struct ConsentRecord: Codable, Identifiable {
    let id: String
    let consentVersion: String?
    let granted: Bool
    let grantedAt: String?
    let revokedAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case consentVersion = "consent_version"
        case granted
        case grantedAt = "granted_at"
        case revokedAt = "revoked_at"
        case createdAt = "created_at"
    }
}

struct ConsentHistoryResponse: Codable {
    let records: [ConsentRecord]
}

struct ConsentActionResponse: Codable {
    let record: ConsentRecord
}

struct LocationReportPayload: Codable {
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double?
    let reportedAt: String
}

struct LocationReportResponse: Codable {
    let report: LocationReportMeta
}

struct LocationReportMeta: Codable {
    let id: String?
    let reportedAt: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case reportedAt = "reported_at"
        case createdAt = "created_at"
    }
}

struct UserLocation: Codable, Identifiable {
    let userId: String
    let name: String
    let personType: String?
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double?
    let reportedAt: String

    var id: String { userId }
}

struct LatestLocationsResponse: Codable {
    let locations: [UserLocation]
}

/// A participant's own reported location — no userId/name/personType, since
/// this always refers to whoever is asking. Used for the participant's own
/// map, distinct from UserLocation (which staff see, for every consented
/// participant).
struct MyLocationReport: Codable, Identifiable {
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double?
    let reportedAt: String

    var id: String { reportedAt }
}

struct MyLocationsResponse: Codable {
    let reports: [MyLocationReport]
}

struct APIErrorResponse: Codable {
    let error: String
}

// MARK: - Documents

enum DocumentType: String, Codable, CaseIterable, Identifiable, Equatable {
    case governmentID = "government_id"
    case socialSecurityCard = "social_security_card"
    case birthCertificate = "birth_certificate"
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .governmentID: return "Government photo ID"
        case .socialSecurityCard: return "Social Security card"
        case .birthCertificate: return "Birth certificate"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .governmentID: return "person.text.rectangle"
        case .socialSecurityCard: return "creditcard"
        case .birthCertificate: return "doc.text"
        case .other: return "doc"
        }
    }

    /// The core three types shown in the "what's on file" checklist.
    /// .other is excluded — it's a catch-all label, not a single checkable item.
    static let coreChecklist: [DocumentType] = [.governmentID, .socialSecurityCard, .birthCertificate]
}

struct DocumentMeta: Codable, Identifiable, Equatable {
    let id: String
    let documentType: String
    let label: String?
    let mimeType: String
    let fileSizeBytes: Int
    let createdAt: String

    var type: DocumentType { DocumentType(rawValue: documentType) ?? .other }
}

struct UploadDocumentRequest: Encodable {
    let documentType: String
    let label: String?
    let mimeType: String
    let fileBase64: String
}

struct UploadDocumentResponse: Codable {
    let document: DocumentMeta
}

struct ListDocumentsResponse: Codable {
    let documents: [DocumentMeta]
}

struct GetDocumentResponse: Codable {
    let document: DocumentMeta
    let fileBase64: String
}

enum LocVaultError: LocalizedError {
    case unauthorized
    case server(String)
    case network(Error)
    case decoding

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .server(let message):
            return message
        case .network(let error):
            return error.localizedDescription
        case .decoding:
            return "Unexpected response from server."
        }
    }
}
