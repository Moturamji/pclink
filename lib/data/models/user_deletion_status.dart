/// Model representing the user's account deletion request status and 15-day grace period.
class UserDeletionStatus {
  final bool isDeleteRequested;
  final DateTime? deleteRequestedAt;
  final DateTime? deleteEffectiveAt;

  const UserDeletionStatus({
    required this.isDeleteRequested,
    this.deleteRequestedAt,
    this.deleteEffectiveAt,
  });

  /// Factory constructor to parse Firebase Realtime Database JSON node.
  factory UserDeletionStatus.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const UserDeletionStatus(isDeleteRequested: false);
    }

    // Use the single clean 'delete' boolean field as requested
    final deleteFlag = json['delete'] == true;

    DateTime? reqAt;
    if (json['deleteRequestedAt'] != null) {
      reqAt = DateTime.tryParse(json['deleteRequestedAt'].toString());
    }

    DateTime? effAt;
    if (json['deleteEffectiveAt'] != null) {
      effAt = DateTime.tryParse(json['deleteEffectiveAt'].toString());
    } else if (reqAt != null) {
      // Default to 15 days from requested time if effective time is missing
      effAt = reqAt.add(const Duration(days: 15));
    }

    return UserDeletionStatus(
      isDeleteRequested: deleteFlag,
      deleteRequestedAt: reqAt,
      deleteEffectiveAt: effAt,
    );
  }

  /// Calculates calendar days remaining until permanent deletion.
  int get daysRemaining {
    if (!isDeleteRequested || deleteEffectiveAt == null) return 0;
    final diff = deleteEffectiveAt!.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return (diff.inSeconds / 86400).ceil();
  }

  /// Calculates total hours remaining until permanent deletion.
  int get hoursRemaining {
    if (!isDeleteRequested || deleteEffectiveAt == null) return 0;
    final diff = deleteEffectiveAt!.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return diff.inHours;
  }

  /// Returns true if 15 full days have passed since deletion was scheduled.
  bool get isPermanentlyExpired {
    if (!isDeleteRequested || deleteEffectiveAt == null) return false;
    return DateTime.now().isAfter(deleteEffectiveAt!);
  }

  Map<String, dynamic> toJson() {
    return {
      'delete': isDeleteRequested,
      if (deleteRequestedAt != null)
        'deleteRequestedAt': deleteRequestedAt!.toIso8601String(),
      if (deleteEffectiveAt != null)
        'deleteEffectiveAt': deleteEffectiveAt!.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'UserDeletionStatus(isDeleteRequested: $isDeleteRequested, daysRemaining: $daysRemaining, effectiveAt: $deleteEffectiveAt)';
  }
}
