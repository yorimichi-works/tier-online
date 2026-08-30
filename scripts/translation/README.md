# Semi-automatic translation batch

Run commands from `functions/`. Firebase Admin uses Application Default
Credentials; never place a service-account key in this repository.

```powershell
npm run translation:fetch -- --project tier-online --confirm-project tier-online
npm run translation:merge -- --source ..\tmp\translations\BATCH\source.json --cached ..\tmp\translations\BATCH\cached.json --codex ..\tmp\translations\BATCH\codex.json
npm run translation:validate -- --source ..\tmp\translations\BATCH\source.json --translated ..\tmp\translations\BATCH\translated.json
npm run translation:import -- --project tier-online --source ..\tmp\translations\BATCH\source.json --translated ..\tmp\translations\BATCH\translated.json --dry-run
npm run translation:import -- --project tier-online --confirm-project tier-online --source ..\tmp\translations\BATCH\source.json --translated ..\tmp\translations\BATCH\translated.json
npm run translation:reset-stale -- --project tier-online --dry-run --stale-hours 24
npm run translation:review-export -- --project tier-online
npm run translation:cache-invalidate -- --key CACHE_HASH
```

`fetch` changes claimed documents to `processing`; therefore it also requires
the exact project confirmation. Use `--dry-run` to inspect candidates without
claiming them. Batch size defaults to `TRANSLATION_BATCH_SIZE` or 100. Stale age
defaults to `TRANSLATION_STALE_HOURS` or 24 hours.

The intended human workflow is: fetch, provide `source.json` together with
`TRANSLATION_PROMPT.md` to Codex, save JSON-only output as `codex.json`, merge it
with `cached.json`, validate the resulting `translated.json`, import with
`--dry-run`, inspect, then perform the confirmed import.
Batch files under `tmp/translations/` are intentionally ignored by Git.

The exact cache is a local JSON file at `tmp/translations/cache.json`. It stores
only source hashes and translated field values, not raw source UGC. Entries with
personal data patterns, URLs, review-required results, failed results, and cache
hits are not inserted. Invalidate a bad entry by its hash; invalid entries remain
auditable but are never reused. Dictionary JSON is intentionally small and only
matching entries are included in each source item.
