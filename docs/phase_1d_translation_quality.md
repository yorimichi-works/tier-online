# Phase 1-D: translation quality baseline

Phase 1-D extends the Phase 1-C manual Codex batch without adding an LLM API,
Scheduler, SEO, advertising, or a translation CMS. Its initial scope is limited
to dictionaries, exact caching, manual-translation protection, locale-level
retranslation, and review-required export.

## Dictionaries

UGC terminology and official names live in
`scripts/translation/dictionaries/`. Only entries matching an item's source
content are copied into `translationContext`; the full dictionaries are never
sent with every batch. UI strings remain in ARB and are not duplicated here.

## Exact cache

The operational cache is local JSON at `tmp/translations/cache.json` and is not
committed. A SHA-256 key covers the minimally normalized source field, field
kind, source and target locales, translation version, prompt version, and
dictionary version. The cache stores the source hash and translated field, but
not the raw source text.

Cache reuse requires every field for a locale to be valid. Cache results are
merged with Codex results and pass the same batch validator. Failed,
review-required, manual-skipped, cached, or personal-data-like inputs are not
inserted. A bad key can be retained but disabled with `isValid = false` through
the cache invalidation CLI.

## Retranslation and review

`contentVersion` remains the source freshness boundary. Current completed
locales are skipped, while only stale or failed automatic locales are selected.
Manual locales are never overwritten; a source edit sets
`manualTranslationOutdated = true`. Imports record translation, prompt, and
dictionary versions plus batch cache/Codex/manual/failure/review statistics.
The review export CLI selects approved public topics whose locale translation
has `reviewRequired == true`.

See `scripts/translation/README.md` for the operator commands.
