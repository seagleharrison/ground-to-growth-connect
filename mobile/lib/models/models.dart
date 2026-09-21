// Ported 1:1 from the native app's Models.swift. Keep the field sets and
// wire keys (snake_case on the API, camelCase in Dart) identical to that
// file so the two clients stay interchangeable against the same backend.

enum PersonType {
  homeless,
  volunteer,
  employee,
  admin;

  static PersonType fromWire(String raw) => PersonType.values.firstWhere(
        (t) => t.name == raw,
        orElse: () => PersonType.homeless,
      );

  String get label => switch (this) {
        PersonType.homeless => 'Person we serve',
        PersonType.volunteer => 'Volunteer',
        PersonType.employee => 'Employee',
        PersonType.admin => 'Admin',
      };

  bool get isStaff => this != PersonType.homeless;
}

enum Gender {
  female,
  male,
  nonbinary,
  other,
  preferNotToSay;

  static Gender fromWire(String raw) => switch (raw) {
        'female' => Gender.female,
        'male' => Gender.male,
        'nonbinary' => Gender.nonbinary,
        'other' => Gender.other,
        _ => Gender.preferNotToSay,
      };

  String get wireValue => switch (this) {
        Gender.preferNotToSay => 'prefer_not_to_say',
        _ => name,
      };

  String get label => switch (this) {
        Gender.female => 'Female',
        Gender.male => 'Male',
        Gender.nonbinary => 'Non-binary',
        Gender.other => 'Other',
        Gender.preferNotToSay => 'Prefer not to say',
      };
}

class User {
  final String id;
  final String personType;
  final String name;
  final String? email;
  final String? gender;
  final String? phone;
  final bool isStaff;
  final bool hasProfilePicture;

  /// Only admin accounts see organization-wide analytics.
  bool get isAdmin => personType == 'admin';

  User({
    required this.id,
    required this.personType,
    required this.name,
    this.email,
    this.gender,
    this.phone,
    required this.isStaff,
    this.hasProfilePicture = false,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        personType: json['personType'] as String,
        name: json['name'] as String,
        email: json['email'] as String?,
        gender: json['gender'] as String?,
        phone: json['phone'] as String?,
        isStaff: json['isStaff'] as bool,
        hasProfilePicture: json['hasProfilePicture'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'personType': personType,
        'name': name,
        'email': email,
        'gender': gender,
        'phone': phone,
        'isStaff': isStaff,
        'hasProfilePicture': hasProfilePicture,
      };
}

class RegisterRequest {
  final String name;
  final String? email;
  final String? gender;
  final String? phone;
  final String personType;
  final String? staffCode;

  RegisterRequest({
    required this.name,
    this.email,
    this.gender,
    this.phone,
    required this.personType,
    this.staffCode,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'gender': gender,
        'phone': phone,
        'personType': personType,
        'staffCode': staffCode,
      };
}

class RegisterResponse {
  final User user;
  final String token;
  final String? message;

  RegisterResponse({required this.user, required this.token, this.message});

  factory RegisterResponse.fromJson(Map<String, dynamic> json) => RegisterResponse(
        user: User.fromJson(json['user'] as Map<String, dynamic>),
        token: json['token'] as String,
        message: json['message'] as String?,
      );
}

class DisclosureResponse {
  final String version;
  final String text;

  DisclosureResponse({required this.version, required this.text});

  factory DisclosureResponse.fromJson(Map<String, dynamic> json) => DisclosureResponse(
        version: json['version'] as String,
        text: json['text'] as String,
      );
}

class ConsentStatus {
  final bool granted;
  final String? consentVersion;
  final String? grantedAt;
  final String? revokedAt;
  final String? lastRecordedAt;

  ConsentStatus({
    required this.granted,
    this.consentVersion,
    this.grantedAt,
    this.revokedAt,
    this.lastRecordedAt,
  });

  factory ConsentStatus.fromJson(Map<String, dynamic> json) => ConsentStatus(
        granted: json['granted'] as bool,
        consentVersion: json['consent_version'] as String?,
        grantedAt: json['granted_at'] as String?,
        revokedAt: json['revoked_at'] as String?,
        lastRecordedAt: json['last_recorded_at'] as String?,
      );
}

class ConsentRecord {
  final String id;
  final String? consentVersion;
  final bool granted;
  final String? grantedAt;
  final String? revokedAt;
  final String createdAt;

  ConsentRecord({
    required this.id,
    this.consentVersion,
    required this.granted,
    this.grantedAt,
    this.revokedAt,
    required this.createdAt,
  });

  factory ConsentRecord.fromJson(Map<String, dynamic> json) => ConsentRecord(
        id: json['id'] as String,
        consentVersion: json['consent_version'] as String?,
        granted: json['granted'] as bool,
        grantedAt: json['granted_at'] as String?,
        revokedAt: json['revoked_at'] as String?,
        createdAt: json['created_at'] as String,
      );
}

class LocationReportPayload {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final String reportedAt;

  LocationReportPayload({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    required this.reportedAt,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'reportedAt': reportedAt,
      };
}

class LocationReportMeta {
  final String? id;
  final String reportedAt;
  final String? createdAt;

  LocationReportMeta({this.id, required this.reportedAt, this.createdAt});

  factory LocationReportMeta.fromJson(Map<String, dynamic> json) => LocationReportMeta(
        id: json['id'] as String?,
        reportedAt: json['reported_at'] as String,
        createdAt: json['created_at'] as String?,
      );
}

/// Staff-only: every consented participant's latest location.
class UserLocation {
  final String userId;
  final String name;
  final String? personType;
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final String reportedAt;

  UserLocation({
    required this.userId,
    required this.name,
    this.personType,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    required this.reportedAt,
  });

  factory UserLocation.fromJson(Map<String, dynamic> json) => UserLocation(
        userId: json['userId'] as String,
        name: json['name'] as String,
        personType: json['personType'] as String?,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
        reportedAt: json['reportedAt'] as String,
      );
}

/// A participant's own reported location — no userId/name, since this always
/// refers to whoever is asking. Distinct from [UserLocation] (what staff see
/// for every consented participant).
class MyLocationReport {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final String reportedAt;

  MyLocationReport({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    required this.reportedAt,
  });

  factory MyLocationReport.fromJson(Map<String, dynamic> json) => MyLocationReport(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
        reportedAt: json['reportedAt'] as String,
      );
}

// MARK: - Documents

enum DocumentType {
  governmentId,
  socialSecurityCard,
  birthCertificate,
  other;

  static DocumentType fromWire(String raw) => switch (raw) {
        'government_id' => DocumentType.governmentId,
        'social_security_card' => DocumentType.socialSecurityCard,
        'birth_certificate' => DocumentType.birthCertificate,
        _ => DocumentType.other,
      };

  String get wireValue => switch (this) {
        DocumentType.governmentId => 'government_id',
        DocumentType.socialSecurityCard => 'social_security_card',
        DocumentType.birthCertificate => 'birth_certificate',
        DocumentType.other => 'other',
      };

  String get label => switch (this) {
        DocumentType.governmentId => 'Government photo ID',
        DocumentType.socialSecurityCard => 'Social Security card',
        DocumentType.birthCertificate => 'Birth certificate',
        DocumentType.other => 'Other',
      };

  /// The core three types shown in the "what's on file" checklist. `.other`
  /// is excluded — it's a catch-all label, not a single checkable item.
  static const List<DocumentType> coreChecklist = [
    DocumentType.governmentId,
    DocumentType.socialSecurityCard,
    DocumentType.birthCertificate,
  ];
}

class DocumentMeta {
  final String id;
  final String documentType;
  final String? label;
  final String mimeType;
  final int fileSizeBytes;
  final String createdAt;

  DocumentMeta({
    required this.id,
    required this.documentType,
    this.label,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.createdAt,
  });

  DocumentType get type => DocumentType.fromWire(documentType);

  factory DocumentMeta.fromJson(Map<String, dynamic> json) => DocumentMeta(
        id: json['id'] as String,
        documentType: json['documentType'] as String,
        label: json['label'] as String?,
        mimeType: json['mimeType'] as String,
        fileSizeBytes: json['fileSizeBytes'] as int,
        createdAt: json['createdAt'] as String,
      );
}

/// Staff-only: which document *types* a participant has on file. Staff never
/// see the documents themselves — only that they exist.
class DocumentsOnFile {
  final String userId;
  final Set<DocumentType> types;

  DocumentsOnFile({required this.userId, required this.types});

  factory DocumentsOnFile.fromJson(Map<String, dynamic> json) => DocumentsOnFile(
        userId: json['userId'] as String,
        types: {for (final t in (json['documentTypes'] as List)) DocumentType.fromWire(t as String)},
      );
}

class GetDocumentResponse {
  final DocumentMeta document;
  final String fileBase64;

  GetDocumentResponse({required this.document, required this.fileBase64});

  factory GetDocumentResponse.fromJson(Map<String, dynamic> json) => GetDocumentResponse(
        document: DocumentMeta.fromJson(json['document'] as Map<String, dynamic>),
        fileBase64: json['fileBase64'] as String,
      );
}

class GgcException implements Exception {
  final String message;
  GgcException(this.message);

  @override
  String toString() => message;
}

/// Organization-wide totals for admins. Counts only — never names, locations
/// or document contents.
class Analytics {
  final int participants;
  final int volunteers;
  final int employees;
  final int admins;
  final int participantsSharing;
  final int activeLast24Hours;
  final int activeLast7Days;
  final int participantsUsingStorage;
  final int participantsWithAllThree;
  final int documentsStored;
  final List<AnalyticsDay> daily;

  Analytics({
    required this.participants,
    required this.volunteers,
    required this.employees,
    required this.admins,
    required this.participantsSharing,
    required this.activeLast24Hours,
    required this.activeLast7Days,
    required this.participantsUsingStorage,
    required this.participantsWithAllThree,
    required this.documentsStored,
    required this.daily,
  });

  factory Analytics.fromJson(Map<String, dynamic> json) {
    final people = json['people'] as Map<String, dynamic>;
    final sharing = json['sharing'] as Map<String, dynamic>;
    final docs = json['documents'] as Map<String, dynamic>;
    return Analytics(
      participants: people['participants'] as int,
      volunteers: people['volunteers'] as int,
      employees: people['employees'] as int,
      admins: people['admins'] as int,
      participantsSharing: sharing['participantsSharing'] as int,
      activeLast24Hours: sharing['activeLast24Hours'] as int,
      activeLast7Days: sharing['activeLast7Days'] as int,
      participantsUsingStorage: docs['participantsUsingStorage'] as int,
      participantsWithAllThree: docs['participantsWithAllThree'] as int,
      documentsStored: docs['documentsStored'] as int,
      daily: [for (final d in (json['daily'] as List)) AnalyticsDay.fromJson(d as Map<String, dynamic>)],
    );
  }

  int get staff => volunteers + employees + admins;
}

class AnalyticsDay {
  final String date; // yyyy-MM-dd, Savannah time
  final int signups;
  final int checkIns;

  AnalyticsDay({required this.date, required this.signups, required this.checkIns});

  factory AnalyticsDay.fromJson(Map<String, dynamic> json) => AnalyticsDay(
        date: json['date'] as String,
        signups: json['signups'] as int,
        checkIns: json['checkIns'] as int,
      );
}

/// Admin only: official pages the Resources content points to that need a look.
class SourceReport {
  final int total;
  final String? lastCheckedAt;
  final List<SourceAttention> needsAttention;

  SourceReport({required this.total, this.lastCheckedAt, required this.needsAttention});

  factory SourceReport.fromJson(Map<String, dynamic> json) => SourceReport(
        total: json['total'] as int,
        lastCheckedAt: (json['lastCheckedAt'] as String?)?.isEmpty == true ? null : json['lastCheckedAt'] as String?,
        needsAttention: [
          for (final a in (json['needsAttention'] as List)) SourceAttention.fromJson(a as Map<String, dynamic>),
        ],
      );
}

class SourceAttention {
  final String url;
  final String reason;
  final int status;

  SourceAttention({required this.url, required this.reason, required this.status});

  factory SourceAttention.fromJson(Map<String, dynamic> json) => SourceAttention(
        url: json['url'] as String,
        reason: json['reason'] as String,
        status: json['status'] as int,
      );
}
