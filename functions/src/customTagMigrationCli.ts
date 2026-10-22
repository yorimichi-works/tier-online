/*
 * Adds structured customTags to legacy topic documents without deleting the
 * existing `tags` string array. Always begin with --dry-run.
 *
 *   npm run tags:migrate -- --dry-run
 *   npm run tags:migrate -- --confirm --project tier-online
 */
import {applicationDefault, getApps, initializeApp} from "firebase-admin/app";
import {FieldPath, FieldValue, getFirestore} from "firebase-admin/firestore";

import {
  customTagsFromUnknown,
  inheritLegacyTagTranslations,
  prepareCustomTags,
  searchTagsFor,
} from "./customTags";
import {firestoreLanguage} from "./internationalization";
import {topicSearchTokens} from "./searchTokens";

const argumentsSet = new Set(process.argv.slice(2));
const dryRun = argumentsSet.has("--dry-run");
const confirmed = argumentsSet.has("--confirm");
const projectIndex = process.argv.indexOf("--project");
const projectId = projectIndex >= 0 ? process.argv[projectIndex + 1] : undefined;
const limitIndex = process.argv.indexOf("--limit");
const requestedLimit = limitIndex >= 0 ? Number(process.argv[limitIndex + 1]) : Infinity;

if (!dryRun && !confirmed) {
  throw new Error("Writes are blocked. Pass --dry-run or --confirm.");
}
if (!Number.isSafeInteger(requestedLimit) && requestedLimit !== Infinity || requestedLimit <= 0) {
  throw new Error("--limit must be a positive integer");
}

if (getApps().length === 0) {
  initializeApp({
    credential: applicationDefault(),
    ...(projectId ? {projectId} : {}),
  });
}

const firestore = getFirestore();

const run = async () => {
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  let scanned = 0;
  let migrated = 0;
  let skippedStructured = 0;
  let skippedFixed = 0;
  let skippedNoTags = 0;
  while (migrated < requestedLimit) {
    const pageSize = Math.min(100, requestedLimit - migrated);
    let query = firestore.collection("topics")
      .orderBy(FieldPath.documentId())
      .limit(pageSize);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) break;
    for (const topic of page.docs) {
      scanned += 1;
      const data = topic.data() as Record<string, unknown>;
      if (customTagsFromUnknown(data.customTags).length > 0) {
        skippedStructured += 1;
        continue;
      }
      // Preset/official tags are canonical metadata, not user free input.
      if (data.isPreset === true || topic.id.startsWith("starter-")) {
        skippedFixed += 1;
        continue;
      }
      const sourceLocale = firestoreLanguage(
        data.sourceLocale ?? data.sourceLanguage ?? data.contentLanguage,
      );
      const rawTags = Array.isArray(data.tags) ? data.tags : [];
      const base = prepareCustomTags(rawTags, sourceLocale, []);
      if (base.length === 0) {
        skippedNoTags += 1;
        continue;
      }
      const customTags = inheritLegacyTagTranslations(base, data.translations);
      const searchTags = searchTagsFor(customTags);
      const items = await topic.ref.collection("items").select("name").get();
      const searchTokens = topicSearchTokens([
        data.title,
        data.description,
        data.category,
        data.categoryId,
        ...searchTags,
        ...items.docs.map((item) => item.data().name),
      ]);
      migrated += 1;
      if (!dryRun) {
        await topic.ref.set({
          customTags,
          searchTags,
          searchTokens,
          customTagsMigratedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
      if (migrated >= requestedLimit) break;
    }
    cursor = page.docs.at(-1);
  }
  console.log(JSON.stringify({
    dryRun,
    projectId: projectId ?? null,
    scanned,
    migrated,
    skippedStructured,
    skippedFixed,
    skippedNoTags,
  }, null, 2));
};

run().catch((error: unknown) => {
  console.error(error instanceof Error ? error.stack : error);
  process.exitCode = 1;
});
