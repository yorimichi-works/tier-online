import assert from "node:assert/strict";
import test from "node:test";

import {normalizeImageName, sharedImageKey} from "./index";

test("image cache names are normalized before hashing", () => {
  assert.equal(normalizeImageName("  ＣＡＦＥ   Latte  "), "cafe latte");
  assert.equal(
    sharedImageKey("  カルボナーラ ", "ja"),
    sharedImageKey("カルボナーラ", "ja"),
  );
  assert.notEqual(
    sharedImageKey("カルボナーラ", "ja"),
    sharedImageKey("カルボナーラ", "en"),
  );
});
