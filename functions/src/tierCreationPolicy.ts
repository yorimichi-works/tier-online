import {HttpsError} from "firebase-functions/v2/https";

export function assertTierCreationAllowed(
  isNewTopic: boolean,
  isAnonymous: boolean,
): void {
  if (isNewTopic && isAnonymous) {
    throw new HttpsError(
      "permission-denied",
      "Tier表の新規作成にはアカウント登録が必要です",
    );
  }
}
