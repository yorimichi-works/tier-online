import assert from "node:assert/strict";
import test from "node:test";

import {assertTierCreationAllowed} from "./tierCreationPolicy";

test("anonymous users cannot create a new Tier topic", () => {
  assert.throws(
    () => assertTierCreationAllowed(true, true),
    (error: unknown) =>
      error instanceof Error &&
      "code" in error &&
      error.code === "permission-denied",
  );
});

test("registered users can create and anonymous users can update legacy topics", () => {
  assert.doesNotThrow(() => assertTierCreationAllowed(true, false));
  assert.doesNotThrow(() => assertTierCreationAllowed(false, true));
});
