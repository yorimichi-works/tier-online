// A deliberately small, Firestore-native first-stage search index. It is not
// intended to replace a dedicated full-text engine at large scale, but it
// avoids filtering an arbitrary first page of topics on the client. Tokens
// include whole words and short 2-character n-grams, which work for Japanese,
// Korean, Chinese, and Latin scripts without locale-specific segmentation.
export function topicSearchTokens(values: readonly unknown[]): string[] {
  const tokens = new Set<string>();
  for (const value of values) {
    if (typeof value !== "string") continue;
    for (const word of value.normalize("NFKC").toLocaleLowerCase()
      .match(/[\p{L}\p{N}]+/gu) ?? []) {
      const chars = [...word].slice(0, 48);
      if (chars.length === 0) continue;
      tokens.add(chars.join(""));
      for (let index = 0; index + 1 < chars.length; index += 1) {
        tokens.add(chars.slice(index, index + 2).join(""));
      }
      if (tokens.size >= 200) return [...tokens].slice(0, 200);
    }
  }
  return [...tokens];
}
