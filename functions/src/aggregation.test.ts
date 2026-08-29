import assert from "node:assert/strict";
import test from "node:test";

import {aggregateTier} from "./aggregation";

test("SとDの中間をBとし、分布と分散を保存する", () => {
  const result = aggregateTier(["item-1"], [
    {s: ["item-1"]},
    {d: ["item-1"]},
  ]);
  assert.equal(result.participants, 2);
  assert.equal(result.community["item-1"], "b");
  assert.equal(result.distributions["item-1"].s, 1);
  assert.equal(result.disagreement["item-1"], 4);
});

test("未配置カードは集合Tierに含めない", () => {
  const result = aggregateTier(["placed", "unplaced"], [
    {a: ["placed"]},
  ]);
  assert.equal(result.community.placed, "a");
  assert.equal(result.community.unplaced, undefined);
});
