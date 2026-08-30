# Phase 1-C: semi-automatic UGC translation batch

Phase 1-C separates database control from translation generation. Deterministic
TypeScript code claims eligible Firestore topics, exports the minimum UGC needed
for translation, validates JSON-only Codex output, and imports only translation
fields. Codex never receives Firebase credentials and never writes Firestore.

## Existing architecture integration

- `sourceLanguage` from Phase 1-A is the sole original-language field. The
  legacy `contentLanguage` is read only as a compatibility fallback.
- Locale codes use the existing five-language profile: `ja`, `en`, `ko`,
  `zh-TW`, and `pt-BR`.
- Existing `topics` and `topics/{id}/items` remain the source collections.
- Original topic and item fields are never updated by the import command.
- The Phase 1-B UI dictionaries and locale selection are unaffected.

## Eligibility

A topic is claimable only when `isPublic == true`, `moderationStatus == approved`,
it is not already processing, and at least one target locale is missing, failed,
pending, or stale for the current content version. The source locale, current
completed/review-required locales, and every manual translation are excluded.

## Firestore fields

- `contentVersion`: monotonically increases when translatable source content
  changes.
- `sourceContentHash`: deterministic source-change detector; it contains no UGC.
- `translationStatus`: `pending`, `processing`, `completed`, `partial`, `failed`,
  or `review_required`.
- `translations.{locale}`: translated UGC plus locale status,
  `sourceContentVersion`, `translationVersion`, `promptVersion`, provider, mode,
  batch ID, and server-side import timestamp.
- `translationBatchId`, `processingStartedAt`: active claim metadata.
- `lastTranslationBatchId`: idempotent import marker.
- `translationUpdatedAt`, `hasTranslationReviewRequired`: operational metadata.

Source edits mark automatic translations pending while preserving manual ones.
An import with a different current `contentVersion` is rejected and returns the
topic to pending.

## Files and operation

Schemas, the Codex prompt, and exact commands are in
[`scripts/translation/README.md`](../scripts/translation/README.md). Local batch
files live below `tmp/translations/` and are ignored by Git because they may
contain production UGC.

Every Firestore command requires `--project`. Mutating commands additionally
require an identical `--confirm-project`; dry runs never write. Firebase Admin
uses Application Default Credentials, and credential files must not be stored in
the repository.

## Explicitly deferred

No LLM API, Scheduler, realtime/comment translation, SEO generation, hreflang,
sitemap work, analytics, advertising, preset generation, or translation cache is
part of Phase 1-C. Phase 1-D adds the initial dictionary/cache/retranslation
layer described in [phase_1d_translation_quality.md](phase_1d_translation_quality.md).
A future worker may replace only the manual Codex step while
retaining the same schemas, validation, and guarded import path.
