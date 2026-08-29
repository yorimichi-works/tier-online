import {initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";

import {aggregateTier, Placements} from "./aggregation";

initializeApp();

export {renderTopic, sitemap} from "./seo";

const googleSearchApiKey = defineSecret("GOOGLE_SEARCH_API_KEY");
const googleSearchEngineId = defineSecret("GOOGLE_SEARCH_ENGINE_ID");

type ImageSearchResult = {
  query: string;
  imageUrl?: string;
  sourceUrl?: string;
};

export const searchTierItemImages = onCall(
  {secrets: [googleSearchApiKey, googleSearchEngineId]},
  async (request): Promise<{results: ImageSearchResult[]}> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "ログインが必要です");
    }
    const rawNames = request.data?.names;
    if (!Array.isArray(rawNames)) {
      throw new HttpsError("invalid-argument", "namesが必要です");
    }
    const names = rawNames
      .filter((name): name is string => typeof name === "string")
      .map((name) => name.trim())
      .filter((name) => name.length > 0 && name.length <= 100);
    if (names.length === 0 || names.length > 30) {
      throw new HttpsError(
        "invalid-argument",
        "一度に検索できるカード名は1〜30件です",
      );
    }
    const locale = ["ja", "ko", "en"].includes(request.data?.locale) ?
      request.data.locale as string : "en";
    const apiKey = googleSearchApiKey.value();
    const engineId = googleSearchEngineId.value();
    if (!apiKey || !engineId) {
      throw new HttpsError(
        "failed-precondition",
        "Google画像検索が設定されていません",
      );
    }

    const results = await Promise.all(names.map(async (query) => {
      const url = new URL("https://customsearch.googleapis.com/customsearch/v1");
      url.search = new URLSearchParams({
        key: apiKey,
        cx: engineId,
        q: query,
        searchType: "image",
        num: "1",
        safe: "active",
        hl: locale,
      }).toString();
      const response = await fetch(url, {
        headers: {"Accept": "application/json"},
      });
      if (!response.ok) {
        const detail = await response.text();
        console.error("Google image search failed", response.status, detail);
        throw new HttpsError(
          "unavailable",
          "Google画像検索へ接続できませんでした",
        );
      }
      const payload = await response.json() as {
        items?: Array<{
          link?: string;
          image?: {contextLink?: string};
        }>;
      };
      const first = payload.items?.[0];
      return {
        query,
        imageUrl: first?.link,
        sourceUrl: first?.image?.contextLink,
      };
    }));
    return {results};
  },
);

export const aggregateTopicTier = onDocumentWritten(
  "topics/{topicId}/submissions/{userId}",
  async (event) => {
    const topicId = event.params.topicId;
    const database = getFirestore();
    const topic = database.collection("topics").doc(topicId);
    const [items, submissions] = await Promise.all([
      topic.collection("items").orderBy("sortIndex").get(),
      topic.collection("submissions").get(),
    ]);
    const itemIds = items.docs.map((document) => document.id);
    const submissionData = submissions.docs.map((document) => ({
      region: (document.data().region as string | undefined) ?? "JP",
      placements: (document.data().placements ?? {}) as Placements,
    }));
    const aggregate = aggregateTier(
      itemIds,
      submissionData.map((submission) => submission.placements),
    );
    await topic.set({
      ...aggregate,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    const regions = new Set(submissionData.map((submission) =>
      submission.region,
    ));
    regions.add("GLOBAL");
    const batch = database.batch();
    for (const region of regions) {
      const regional = region === "GLOBAL" ? submissionData :
        submissionData.filter((submission) => submission.region === region);
      const regionAggregate = aggregateTier(
        itemIds,
        regional.map((submission) => submission.placements),
      );
      batch.set(database.collection("tierRegionStats").doc(
        `${topicId}_${region}`,
      ), {
        tierId: topicId,
        region,
        ...regionAggregate,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    await batch.commit();
  },
);

export const aggregateTopicLikes = onDocumentWritten(
  "topics/{topicId}/likes/{userId}",
  async (event) => {
    const topic = getFirestore().collection("topics").doc(event.params.topicId);
    const snapshot = await topic.collection("likes").count().get();
    await topic.set({
      likeCount: snapshot.data().count,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  },
);
