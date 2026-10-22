/// Called inside the Firestore transaction with its latest snapshot, never
/// with a device preference. Replacing a stale local choice cannot remove a
/// different vote made by another device.
({Map<String, String> votes, String? reaction}) toggleTalkVote(
  Map<String, String> latest,
  String target,
  bool positive,
) {
  final votes = Map<String, String>.of(latest);
  final intent = positive ? 'up' : 'down';
  final reaction = votes[target] == intent ? null : intent;
  if (reaction == null) {
    votes.remove(target);
  } else {
    votes[target] = reaction;
  }
  return (votes: votes, reaction: reaction);
}
