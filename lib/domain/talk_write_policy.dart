/// These declarations are a compatibility gate, not authentication. Rules
/// independently enforce topic visibility and the authenticated author UID.
abstract final class TalkClientVersion {
  static const protocol = 2;
  // Keep in sync with pubspec.yaml's release build number.
  static const build = 2;
  static const fields = {
    'clientProtocolVersion': protocol,
    'clientBuild': build,
  };
}

enum TalkWriteBlock { paused, updateRequired }

class TalkWriteUnavailable implements Exception {
  const TalkWriteUnavailable(this.reason);
  final TalkWriteBlock reason;
  @override
  String toString() => reason == TalkWriteBlock.updateRequired
      ? 'Update the app to post replies or reactions.'
      : 'Posting is temporarily paused. Your local data is preserved.';
}

class TalkWritePolicy {
  const TalkWritePolicy({
    required this.enabled,
    required this.readProtocol,
    required this.minProtocol,
    required this.minBuild,
  });
  const TalkWritePolicy.legacy()
    : enabled = false,
      readProtocol = 1,
      minProtocol = 2,
      minBuild = 2;
  factory TalkWritePolicy.fromMap(Map<String, dynamic>? data) =>
      TalkWritePolicy(
        enabled: data?['writesEnabled'] == true,
        readProtocol: data?['readProtocolVersion'] is int
            ? data!['readProtocolVersion'] as int
            : 2,
        minProtocol: data?['minProtocolVersion'] is int
            ? data!['minProtocolVersion'] as int
            : -1,
        minBuild: data?['minClientBuild'] is int
            ? data!['minClientBuild'] as int
            : -1,
      );
  final bool enabled;
  final int readProtocol;
  final int minProtocol;
  final int minBuild;
  TalkWriteBlock? get block {
    if (!enabled || minProtocol < 2 || minBuild < 2) {
      return TalkWriteBlock.paused;
    }
    if (readProtocol != TalkClientVersion.protocol ||
        minProtocol > TalkClientVersion.protocol ||
        minBuild > TalkClientVersion.build) {
      return TalkWriteBlock.updateRequired;
    }
    return null;
  }

  void requireWritable() {
    final reason = block;
    if (reason != null) throw TalkWriteUnavailable(reason);
  }
}
