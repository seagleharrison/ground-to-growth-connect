// Ported 1:1 from the native app's Models.swift. Keep the field sets and
// wire keys (snake_case on the API, camelCase in Dart) identical to that
// file so the two clients stay interchangeable against the same backend.

enum PersonType {
  homeless,
  volunteer,
  admin;

  static PersonType fromWire(String raw) => PersonType.values.firstWhere(
    (t) => t.name == raw,
    orElse: () => PersonType.homeless,
  );

  String get label => switch (this) {
    PersonType.homeless => 'Person we serve',
    PersonType.volunteer => 'Volunteer',
    PersonType.admin => 'Admin',
  };

  bool get isStaff => this != PersonType.homeless;
}

/// Which version of the app someone is looking at. An admin can look at the
/// app the way volunteers and participants see it (a preview) without changing
/// their account or what the server lets them do.
enum AppView {
  admin('Admin'),
  volunteer('Volunteer'),
  participant('Getting support');

  final String label;
  const AppView(this.label);
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

  /// Shown once, at sign-up: the only way back into this account if the
  /// person signs out, loses their phone, or gets a new number. It is never
  /// sent again after this — write it down or lose it for good.
  final String? recoveryCode;

  RegisterResponse({required this.user, required this.token, this.message, this.recoveryCode});

  factory RegisterResponse.fromJson(Map<String, dynamic> json) =>
      RegisterResponse(
        user: User.fromJson(json['user'] as Map<String, dynamic>),
        token: json['token'] as String,
        message: json['message'] as String?,
        recoveryCode: json['recoveryCode'] as String?,
      );
}

/// The response to entering a recovery code: back in on the same account,
/// with a fresh token (any other device using the old one is signed out).
class RecoverResponse {
  final User user;
  final String token;

  RecoverResponse({required this.user, required this.token});

  factory RecoverResponse.fromJson(Map<String, dynamic> json) => RecoverResponse(
        user: User.fromJson(json['user'] as Map<String, dynamic>),
        token: json['token'] as String,
      );
}

class DisclosureResponse {
  final String version;
  final String text;

  DisclosureResponse({required this.version, required this.text});

  factory DisclosureResponse.fromJson(Map<String, dynamic> json) =>
      DisclosureResponse(
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

  factory LocationReportMeta.fromJson(Map<String, dynamic> json) =>
      LocationReportMeta(
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

  /// A colleague sharing their own location, rather than someone being
  /// supported. The staff map marks these differently so it's never mistaken
  /// for a participant.
  bool get isStaffPerson => PersonType.fromWire(personType ?? 'homeless').isStaff;
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

  factory MyLocationReport.fromJson(Map<String, dynamic> json) =>
      MyLocationReport(
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

/// A participant's own appointment — private to them; nothing staff-facing
/// ever reads this.
class Appointment {
  final String id;
  final String title;
  final String? notes;
  final String? location;
  final String startsAt;
  final String createdAt;

  Appointment({
    required this.id,
    required this.title,
    this.notes,
    this.location,
    required this.startsAt,
    required this.createdAt,
  });

  DateTime get startsAtLocal => DateTime.parse(startsAt).toLocal();

  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
    id: json['id'] as String,
    title: json['title'] as String,
    notes: json['notes'] as String?,
    location: json['location'] as String?,
    startsAt: json['startsAt'] as String,
    createdAt: json['createdAt'] as String,
  );
}

/// What someone can ask for help with. The wire value is what the server stores.
enum HelpCategory {
  food('food', 'Food'),
  shelter('shelter', 'A place to stay'),
  ride('ride', 'A ride'),
  documents('documents', 'ID or papers'),
  clothing('clothing', 'Clothing or hygiene'),
  health('health', 'Health'),
  work('work', 'Work'),
  other('other', 'Something else');

  final String wireValue;
  final String label;
  const HelpCategory(this.wireValue, this.label);

  static HelpCategory fromWire(String wire) =>
      HelpCategory.values.firstWhere((c) => c.wireValue == wire, orElse: () => HelpCategory.other);
}

/// The appointment someone attached to a help request, so a volunteer knows
/// where and when to take them. Nothing else about their calendar is shared.
class HelpAppointment {
  final String id;
  final String title;
  final String? location;
  final String startsAt;

  HelpAppointment({required this.id, required this.title, this.location, required this.startsAt});

  DateTime get startsAtLocal => DateTime.parse(startsAt).toLocal();

  factory HelpAppointment.fromJson(Map<String, dynamic> json) => HelpAppointment(
    id: json['id'] as String,
    title: json['title'] as String,
    location: json['location'] as String?,
    startsAt: json['startsAt'] as String,
  );
}

/// One "I need help with..." request. The same shape serves both sides: the
/// person who asked sees status and the helper's first name; volunteers and
/// admins also get who asked ([userId], [name]) and whether they're the helper.
class HelpRequest {
  final String id;
  final HelpCategory category;
  final String? note;
  final String status; // open | claimed | done
  final String createdAt;
  final String? helperName;
  final HelpAppointment? appointment;

  // Staff view only.
  final String? userId;
  final String? name;
  final bool claimedByMe;

  HelpRequest({
    required this.id,
    required this.category,
    this.note,
    required this.status,
    required this.createdAt,
    this.helperName,
    this.appointment,
    this.userId,
    this.name,
    this.claimedByMe = false,
  });

  bool get isOpen => status == 'open';
  bool get isClaimed => status == 'claimed';
  bool get isDone => status == 'done';
  DateTime get createdAtLocal => DateTime.parse(createdAt).toLocal();

  factory HelpRequest.fromJson(Map<String, dynamic> json) => HelpRequest(
    id: json['id'] as String,
    category: HelpCategory.fromWire(json['category'] as String),
    note: json['note'] as String?,
    status: json['status'] as String,
    createdAt: json['createdAt'] as String,
    helperName: json['helperName'] as String?,
    appointment: json['appointment'] == null ? null : HelpAppointment.fromJson(json['appointment'] as Map<String, dynamic>),
    userId: json['userId'] as String?,
    name: json['name'] as String?,
    claimedByMe: json['claimedByMe'] as bool? ?? false,
  );
}

/// Someone you can message (or have messaged), with the latest message.
/// [role] is team (Ground to Growth staff), volunteer, or participant.
class Conversation {
  final String userId;
  final String name;
  final String role;
  final String? lastMessage;
  final String? lastAt;
  final int unread;

  /// False once the help that opened this chat has ended (or it was blocked
  /// or paused): the history can still be read but nothing new can be sent.
  final bool canSend;

  Conversation({
    required this.userId,
    required this.name,
    required this.role,
    this.lastMessage,
    this.lastAt,
    this.unread = 0,
    this.canSend = true,
  });

  DateTime? get lastAtLocal => lastAt == null ? null : DateTime.parse(lastAt!).toLocal();

  String get roleLabel => switch (role) {
    'team' => 'Ground to Growth team',
    'volunteer' => 'Volunteer',
    _ => 'Getting support',
  };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    userId: json['userId'] as String,
    name: json['name'] as String,
    role: json['role'] as String,
    lastMessage: json['lastMessage'] as String?,
    lastAt: json['lastAt'] as String?,
    unread: json['unread'] as int? ?? 0,
    canSend: json['canSend'] as bool? ?? true,
  );
}

class ChatMessage {
  final String id;
  final bool fromMe;
  final String body;
  final String createdAt;

  ChatMessage({required this.id, required this.fromMe, required this.body, required this.createdAt});

  DateTime get createdAtLocal => DateTime.parse(createdAt).toLocal();

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    fromMe: json['fromMe'] as bool,
    body: json['body'] as String,
    createdAt: json['createdAt'] as String,
  );
}

/// A person as admins see them in safety screens.
class PersonRef {
  final String userId;
  final String name;
  final String role;
  PersonRef({required this.userId, required this.name, required this.role});

  factory PersonRef.fromJson(Map<String, dynamic> json) =>
      PersonRef(userId: json['userId'] as String, name: json['name'] as String, role: json['role'] as String? ?? 'participant');
}

/// "Report a problem", as an admin reads it.
class SafetyReport {
  final String id;
  final String status; // open | resolved
  final String createdAt;
  final String? reason;
  final PersonRef reporter;
  final PersonRef subject;

  SafetyReport({
    required this.id,
    required this.status,
    required this.createdAt,
    this.reason,
    required this.reporter,
    required this.subject,
  });

  bool get isOpen => status == 'open';
  DateTime get createdAtLocal => DateTime.parse(createdAt).toLocal();

  factory SafetyReport.fromJson(Map<String, dynamic> json) => SafetyReport(
    id: json['id'] as String,
    status: json['status'] as String,
    createdAt: json['createdAt'] as String,
    reason: json['reason'] as String?,
    reporter: PersonRef.fromJson(json['reporter'] as Map<String, dynamic>),
    subject: PersonRef.fromJson(json['subject'] as Map<String, dynamic>),
  );
}

/// Who has been talking to whom — no message text until an admin opens it.
class AdminConversation {
  final PersonRef a;
  final PersonRef b;
  final int count;
  final String lastAt;
  final bool flagged;

  AdminConversation({required this.a, required this.b, required this.count, required this.lastAt, required this.flagged});

  DateTime get lastAtLocal => DateTime.parse(lastAt).toLocal();

  factory AdminConversation.fromJson(Map<String, dynamic> json) => AdminConversation(
    a: PersonRef.fromJson(json['a'] as Map<String, dynamic>),
    b: PersonRef.fromJson(json['b'] as Map<String, dynamic>),
    count: json['count'] as int,
    lastAt: json['lastAt'] as String,
    flagged: json['flagged'] as bool? ?? false,
  );
}

class AdminMessage {
  final String id;
  final String senderId;
  final String body;
  final String createdAt;
  AdminMessage({required this.id, required this.senderId, required this.body, required this.createdAt});

  DateTime get createdAtLocal => DateTime.parse(createdAt).toLocal();

  factory AdminMessage.fromJson(Map<String, dynamic> json) => AdminMessage(
    id: json['id'] as String,
    senderId: json['senderId'] as String,
    body: json['body'] as String,
    createdAt: json['createdAt'] as String,
  );
}

class VolunteerInfo {
  final String userId;
  final String name;
  final bool approved;
  final bool paused;
  final String createdAt;

  VolunteerInfo({required this.userId, required this.name, required this.approved, required this.paused, required this.createdAt});

  factory VolunteerInfo.fromJson(Map<String, dynamic> json) => VolunteerInfo(
    userId: json['userId'] as String,
    name: json['name'] as String,
    approved: json['approved'] as bool,
    paused: json['paused'] as bool? ?? false,
    createdAt: json['createdAt'] as String,
  );
}

class AccessLogEntry {
  final String admin;
  final String a;
  final String b;
  final String createdAt;
  AccessLogEntry({required this.admin, required this.a, required this.b, required this.createdAt});

  DateTime get createdAtLocal => DateTime.parse(createdAt).toLocal();

  factory AccessLogEntry.fromJson(Map<String, dynamic> json) => AccessLogEntry(
    admin: json['admin'] as String,
    a: json['a'] as String,
    b: json['b'] as String,
    createdAt: json['createdAt'] as String,
  );
}

/// Staff-only: which document *types* a participant has on file. Staff never
/// see the documents themselves — only that they exist.
class DocumentsOnFile {
  final String userId;
  final Set<DocumentType> types;

  DocumentsOnFile({required this.userId, required this.types});

  factory DocumentsOnFile.fromJson(Map<String, dynamic> json) =>
      DocumentsOnFile(
        userId: json['userId'] as String,
        types: {
          for (final t in (json['documentTypes'] as List))
            DocumentType.fromWire(t as String),
        },
      );
}

class GetDocumentResponse {
  final DocumentMeta document;
  final String fileBase64;

  GetDocumentResponse({required this.document, required this.fileBase64});

  factory GetDocumentResponse.fromJson(Map<String, dynamic> json) =>
      GetDocumentResponse(
        document: DocumentMeta.fromJson(
          json['document'] as Map<String, dynamic>,
        ),
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
      admins: people['admins'] as int,
      participantsSharing: sharing['participantsSharing'] as int,
      activeLast24Hours: sharing['activeLast24Hours'] as int,
      activeLast7Days: sharing['activeLast7Days'] as int,
      participantsUsingStorage: docs['participantsUsingStorage'] as int,
      participantsWithAllThree: docs['participantsWithAllThree'] as int,
      documentsStored: docs['documentsStored'] as int,
      daily: [
        for (final d in (json['daily'] as List))
          AnalyticsDay.fromJson(d as Map<String, dynamic>),
      ],
    );
  }

  int get staff => volunteers + admins;
}

class AnalyticsDay {
  final String date; // yyyy-MM-dd, Savannah time
  final int signups;
  final int checkIns;

  AnalyticsDay({
    required this.date,
    required this.signups,
    required this.checkIns,
  });

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

  /// Pages whose websites refuse automatic checks. Not a problem in itself; an
  /// admin can open them now and then.
  final List<SourceAttention> cannotCheck;

  SourceReport({
    required this.total,
    this.lastCheckedAt,
    required this.needsAttention,
    this.cannotCheck = const [],
  });

  factory SourceReport.fromJson(Map<String, dynamic> json) => SourceReport(
    total: json['total'] as int,
    lastCheckedAt: (json['lastCheckedAt'] as String?)?.isEmpty == true
        ? null
        : json['lastCheckedAt'] as String?,
    needsAttention: [
      for (final a in (json['needsAttention'] as List))
        SourceAttention.fromJson(a as Map<String, dynamic>),
    ],
    cannotCheck: [
      for (final a in (json['cannotCheck'] as List? ?? []))
        SourceAttention.fromJson(a as Map<String, dynamic>),
    ],
  );
}

class SourceAttention {
  final String url;
  final String reason;
  final int status;

  SourceAttention({
    required this.url,
    required this.reason,
    required this.status,
  });

  factory SourceAttention.fromJson(Map<String, dynamic> json) =>
      SourceAttention(
        url: json['url'] as String,
        reason: json['reason'] as String,
        status: json['status'] as int,
      );
}
