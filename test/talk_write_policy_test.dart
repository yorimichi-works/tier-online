import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tier_table_online/domain/talk_reactions.dart';
import 'package:tier_table_online/domain/talk_write_policy.dart';

void main() {
  const enabled = {
    'writesEnabled': true,
    'readProtocolVersion': 2,
    'minProtocolVersion': 2,
    'minClientBuild': 2,
  };
  test('policy missing, malformed, paused or incompatible fails closed', () {
    for (final data in [
      null,
      <String, dynamic>{},
      {...enabled, 'writesEnabled': false},
      {...enabled, 'minProtocolVersion': '2'},
      {...enabled, 'minClientBuild': 1},
    ]) {
      expect(TalkWritePolicy.fromMap(data).block, TalkWriteBlock.paused);
    }
    expect(TalkWritePolicy.fromMap(enabled).block, isNull);
    expect(
      TalkWritePolicy.fromMap({...enabled, 'minClientBuild': 3}).block,
      TalkWriteBlock.updateRequired,
    );
    expect(
      TalkWritePolicy.fromMap({...enabled, 'minProtocolVersion': 3}).block,
      TalkWriteBlock.updateRequired,
    );
    expect(const TalkWritePolicy.legacy().readProtocol, 1);
  });
  test('the declared client build matches the release build number', () {
    final version = RegExp(
      r'^version: .*\+(\d+)$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!;
    expect(TalkClientVersion.build, int.parse(version.group(1)!));
  });
  test(
    'the latest vote decides a toggle while other targets are preserved',
    () {
      final result = toggleTalkVote(
        {'root': 'down', 'reply': 'up'},
        'root',
        true,
      );
      expect(result.votes, {'root': 'up', 'reply': 'up'});
      expect(toggleTalkVote(result.votes, 'root', true).votes, {'reply': 'up'});
    },
  );
}
