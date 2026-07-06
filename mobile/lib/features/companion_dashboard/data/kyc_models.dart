import 'package:companion_ranchi/core/models/json_utils.dart';

/// KYC document types a companion must submit (mirrors `KycDocType`).
class KycDocType {
  KycDocType._();
  static const String governmentId = 'GOVERNMENT_ID';
  static const String selfie = 'SELFIE';

  static String label(String value) {
    switch (value) {
      case governmentId:
        return 'Government ID';
      case selfie:
        return 'Selfie';
      default:
        return value;
    }
  }
}

/// Overall KYC review states (mirrors `KycStatus`).
class KycStatusValue {
  KycStatusValue._();
  static const String pending = 'PENDING';
  static const String submitted = 'SUBMITTED';
  static const String approved = 'APPROVED';
  static const String rejected = 'REJECTED';

  static String label(String value) {
    switch (value) {
      // Backend sets PENDING on a freshly submitted document (schema default)
      // — it means "awaiting review", not "not started".
      case pending:
      case submitted:
        return 'Under review';
      case approved:
        return 'Approved';
      case rejected:
        return 'Rejected';
      default:
        return value;
    }
  }
}

/// One uploaded KYC document (kyc_documents row).
class KycDocument {
  const KycDocument({
    required this.id,
    required this.docType,
    required this.documentUrl,
    required this.status,
    this.documentNumber,
    this.reviewNotes,
  });

  final String id;

  /// `GOVERNMENT_ID` | `SELFIE`.
  final String docType;
  final String documentUrl;

  /// `PENDING` | `SUBMITTED` | `APPROVED` | `REJECTED`.
  final String status;
  final String? documentNumber;
  final String? reviewNotes;

  factory KycDocument.fromJson(Map<String, dynamic> json) => KycDocument(
        id: J.asString(json['id']),
        docType: J.asString(json['docType']),
        documentUrl: J.asString(json['documentUrl']),
        status: J.asString(json['status'], KycStatusValue.submitted),
        documentNumber: J.asStringOrNull(json['documentNumber']),
        reviewNotes: J.asStringOrNull(json['reviewNotes']),
      );
}

/// Overall KYC state for the signed-in companion (`GET /kyc/status`).
class KycStatus {
  const KycStatus({
    required this.status,
    required this.documents,
  });

  /// Overall KYC status across the required documents.
  final String status;
  final List<KycDocument> documents;

  bool get isApproved => status == KycStatusValue.approved;

  bool _hasApproved(String docType) =>
      documents.any((d) => d.docType == docType && d.status == KycStatusValue.approved);

  bool _hasAny(String docType) =>
      documents.any((d) => d.docType == docType);

  /// Whether a (any status) Government ID has been uploaded.
  bool get hasGovernmentId => _hasAny(KycDocType.governmentId);

  /// Whether a (any status) Selfie has been uploaded.
  bool get hasSelfie => _hasAny(KycDocType.selfie);

  /// Both required documents have been submitted.
  bool get hasBothDocuments => hasGovernmentId && hasSelfie;

  /// Both required documents are approved.
  bool get bothApproved =>
      _hasApproved(KycDocType.governmentId) && _hasApproved(KycDocType.selfie);

  factory KycStatus.fromJson(Map<String, dynamic> json) {
    final docs = J
        .asMapList(json['documents'] ?? json['docs'])
        .map(KycDocument.fromJson)
        .toList(growable: false);
    return KycStatus(
      status: J.asString(json['status'], KycStatusValue.pending),
      documents: docs,
    );
  }

  static const empty = KycStatus(
    status: KycStatusValue.pending,
    documents: [],
  );
}
