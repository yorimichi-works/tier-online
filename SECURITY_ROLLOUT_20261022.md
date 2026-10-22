# Functions security rollout preparation — 2026-10-22

Scope: existing tier-online Functions only. Hosting, rules, IAM, environment variables, authentication, and audience are unchanged. No native distribution.

The currently deployed Functions ZIP contains source not committed in main. All 41 deployed TypeScript files match the original developer working tree. The original working tree was preserved. Commit 07b80d0a3f9d651cd9c0af2216334b71f47e3745 records that already deployed source on deploy/security-audit-20261022; it does not introduce those features to production.

Dependency commit c19ddfab2f9d4c788748476335a9fe4ae5cec3e9 changes only functions/package-lock.json: @grpc/grpc-js 1.14.4 → 1.14.6, brace-expansion 2.1.4 → 2.1.7, proxy-addr 2.0.7 → 2.0.8, qs 6.15.3 → 6.16.1. Every other lock entry is identical to the deployed lock.

Validation: Node 22.23.4, TypeScript build PASS, 74/74 tests PASS with one worker. The archived baseline SEO test also fails with the original gRPC 1.14.4 because it calls Firestore without initialization; a903cd5780efc935949786fe5568353415befc80 adds an isolated Firestore mock to that test only. Existing dictionary fixtures are materialized for validation. No runtime TypeScript implementation was changed.

Rollback: original source ZIP SHA256 5fe34e124262ecc6f6e43125671251fae2e6c436799f312b4193ec426a2e4126, GCS source generation 1788450282784516 (asia-northeast1) / 1788450289948969 (us-central1). Per-function revisions, source generations, protected-settings and IAM fingerprints are recorded outside Git in the local deployment evidence. Secret/environment values are not committed.

The publication artifact preserves every original ZIP entry except the dependency lock and the isolated SEO test source/compiled test/map. Application implementation and the environment file are byte-for-byte unchanged. The source-only Cloud Functions v2 update mask preserves service configuration and IAM. Any existing Firebase CLI source-cache hash will be invalidated when publishing outside that cache path; no access-related labels are changed. This uses the existing Cloud Functions service and authentication; it does not enable APIs or add services.

Production status: all 40 existing Functions were deployed and individually verified. A fresh project inventory confirmed all 40 current revisions, source generations and execution settings. Managed production Node patch level remains unverified.

API contract: https://docs.cloud.google.com/functions/docs/reference/rest/v2/projects.locations.functions/patch


## Completed production rollout

Verified at 2026-10-22T11:47:40.698Z. The application source is a903cd5780efc935949786fe5568353415befc80; the dependency-only commit is c19ddfab2f9d4c788748476335a9fe4ae5cec3e9. Every deployed ZIP has SHA256 0b60efbb6d2c756bd618653c38ebd647d596605aeeb886dea26c47b47e430582. All 40 Cloud Builds succeeded. Runtime settings, environment variables, IAM and public URIs were unchanged. Main/master and Hosting were not changed. Sites and vending were held.

Validation used 28 CORS OPTIONS responses, five early 404 paths and the existing robots 200 response. Five Firestore event functions and one scheduled deletion function were checked through Cloud Run Ready/current revision; their business triggers were not invoked. No data-changing, contact-sending, ad-bonus or paid-feature tests were performed.

One operation-status GET returned a transient HTTP 500 for adminListTopics. The same operation subsequently returned HTTP 200/done without an operation error; all verification passed. The deployment was not replayed. A preflight comparison for the first event function stopped before upload because filter ordering differed across API responses. A permutation proof showed that only ordering differed; comparison was canonicalized without changing any production filter.

Full operation IDs, source generations, before/after revisions and checks are recorded in [the rollout evidence](docs/SECURITY_ROLLOUT_20261022.json). The exact original source ZIPs remain preserved in the local rollback directory; environment values and credentials are not included in this repository evidence.

| Function | Region | Before revision | After revision |
|---|---|---|---|
| onReportWritten | asia-northeast1 | onreportwritten-00019-xez | onreportwritten-00020-xiv |
| aggregateTopicLikes | asia-northeast1 | aggregatetopiclikes-00019-moz | aggregatetopiclikes-00020-fud |
| aggregateTalkReplyCount | asia-northeast1 | aggregatetalkreplycount-00003-xat | aggregatetalkreplycount-00004-waf |
| aggregateTopicCommentCount | asia-northeast1 | aggregatetopiccommentcount-00003-wib | aggregatetopiccommentcount-00004-boh |
| aggregateTopicTier | asia-northeast1 | aggregatetopictier-00019-pir | aggregatetopictier-00020-paf |
| getDailyCreateStatus | us-central1 | getdailycreatestatus-00019-ruq | getdailycreatestatus-00020-siw |
| registerAnonymousLifecycle | us-central1 | registeranonymouslifecycle-00002-xok | registeranonymouslifecycle-00003-tiy |
| cleanupExpiredAnonymousArtifacts | us-central1 | cleanupexpiredanonymousartifacts-00002-wab | cleanupexpiredanonymousartifacts-00003-yud |
| sitemap | us-central1 | sitemap-00022-zub | sitemap-00023-mup |
| canonicalLocaleRedirect | us-central1 | canonicallocaleredirect-00007-cev | canonicallocaleredirect-00008-das |
| deleteTierTopic | us-central1 | deletetiertopic-00019-sum | deletetiertopic-00020-gen |
| lookupSharedImageVariants | us-central1 | lookupsharedimagevariants-00004-heg | lookupsharedimagevariants-00005-vap |
| searchTierItemImages | us-central1 | searchtieritemimages-00025-goc | searchtieritemimages-00026-kom |
| confirmCreateAdBonus | us-central1 | confirmcreateadbonus-00019-boz | confirmcreateadbonus-00020-zej |
| publishTierTopic | us-central1 | publishtiertopic-00021-kuh | publishtiertopic-00022-poh |
| submitContactRequest | us-central1 | submitcontactrequest-00016-mof | submitcontactrequest-00017-vex |
| setDisplayName | us-central1 | setdisplayname-00004-xeh | setdisplayname-00005-lup |
| adminDeleteTopic | us-central1 | admindeletetopic-00010-kaz | admindeletetopic-00011-xiy |
| adminSetTopicPublic | us-central1 | adminsettopicpublic-00010-voh | adminsettopicpublic-00011-jix |
| adminSetSharedImageHidden | us-central1 | adminsetsharedimagehidden-00016-mar | adminsetsharedimagehidden-00017-qis |
| getAdminStatus | us-central1 | getadminstatus-00008-gor | getadminstatus-00009-xud |
| updateNgWordConfig | us-central1 | updatengwordconfig-00019-mej | updatengwordconfig-00020-vuz |
| renderHome | us-central1 | renderhome-00020-kij | renderhome-00021-ruw |
| sitemapLocale | us-central1 | sitemaplocale-00005-tov | sitemaplocale-00006-zep |
| deleteUserAccount | us-central1 | deleteuseraccount-00016-heq | deleteuseraccount-00017-dav |
| continueAnonymousAccountTransfer | us-central1 | continueanonymousaccounttransfer-00003-sok | continueanonymousaccounttransfer-00004-zew |
| getNgWordConfig | us-central1 | getngwordconfig-00019-mix | getngwordconfig-00020-cah |
| setModerationStatus | us-central1 | setmoderationstatus-00019-qak | setmoderationstatus-00020-qop |
| reportContent | us-central1 | reportcontent-00021-mez | reportcontent-00022-nes |
| renderTopic | us-central1 | rendertopic-00026-nep | rendertopic-00027-deq |
| startAnonymousAccountTransfer | us-central1 | startanonymousaccounttransfer-00003-pob | startanonymousaccounttransfer-00004-jom |
| adminDeleteSharedImage | us-central1 | admindeletesharedimage-00016-yub | admindeletesharedimage-00017-noh |
| adminModerateTalk | us-central1 | adminmoderatetalk-00008-haj | adminmoderatetalk-00009-tum |
| adminSearchSharedImages | us-central1 | adminsearchsharedimages-00016-del | adminsearchsharedimages-00017-yok |
| requestCreateAdBonusToken | us-central1 | requestcreateadbonustoken-00019-wob | requestcreateadbonustoken-00020-dor |
| adminListTopics | us-central1 | adminlisttopics-00011-rif | adminlisttopics-00012-duc |
| contributeItemImage | us-central1 | contributeitemimage-00002-tet | contributeitemimage-00003-zur |
| setTopicVisibility | us-central1 | settopicvisibility-00002-rab | settopicvisibility-00003-ley |
| robots | us-central1 | robots-00005-xer | robots-00006-len |
| setTalkReaction | us-central1 | settalkreaction-00004-bik | settalkreaction-00005-get |
