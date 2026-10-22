# Functions security rollout preparation — 2026-10-22

Scope: existing tier-online Functions only. Hosting, rules, IAM, environment variables, authentication, and audience are unchanged. No native distribution.

The currently deployed Functions ZIP contains source not committed in main. All 41 deployed TypeScript files match the original developer working tree. The original working tree was preserved. Commit 07b80d0a3f9d651cd9c0af2216334b71f47e3745 records that already deployed source on deploy/security-audit-20261022; it does not introduce those features to production.

Dependency commit c19ddfab2f9d4c788748476335a9fe4ae5cec3e9 changes only functions/package-lock.json: @grpc/grpc-js 1.14.4 → 1.14.6, brace-expansion 2.1.4 → 2.1.7, proxy-addr 2.0.7 → 2.0.8, qs 6.15.3 → 6.16.1. Every other lock entry is identical to the deployed lock.

Validation: Node 22.23.4, TypeScript build PASS, 74/74 tests PASS with one worker. The archived baseline SEO test also fails with the original gRPC 1.14.4 because it calls Firestore without initialization; a903cd5780efc935949786fe5568353415befc80 adds an isolated Firestore mock to that test only. Existing dictionary fixtures are materialized for validation. No runtime TypeScript implementation was changed.

Rollback: original source ZIP SHA256 5fe34e124262ecc6f6e43125671251fae2e6c436799f312b4193ec426a2e4126, GCS source generation 1788450282784516 (asia-northeast1) / 1788450289948969 (us-central1). Per-function revisions, source generations, protected-settings and IAM fingerprints are recorded outside Git in the local deployment evidence. Secret/environment values are not committed.

The publication artifact preserves every original ZIP entry except the dependency lock and the isolated SEO test source/compiled test/map. Application implementation and the environment file are byte-for-byte unchanged. The source-only Cloud Functions v2 update mask preserves service configuration and IAM. Any existing Firebase CLI source-cache hash will be invalidated when publishing outside that cache path; no access-related labels are changed. This uses the existing Cloud Functions service and authentication; it does not enable APIs or add services.

Status at this commit: prepared and tested; NOT DEPLOYED. A provider operation and live checks are required before claiming production reflection. Managed production Node patch level remains unverified.

API contract: https://docs.cloud.google.com/functions/docs/reference/rest/v2/projects.locations.functions/patch
