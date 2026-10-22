import assert from "node:assert/strict";
import test from "node:test";

import {
  aggregateTier,
  applySubmissionDelta,
  incrementalAggregateFrom,
} from "./aggregation";

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

test("差分集計はsubmission更新・削除後も全件集計と一致する", () => {
  const itemIds = ["a", "b"];
  const first = {s: ["a"], d: ["b"]};
  const second = {a: ["a", "b"]};
  const baseline = aggregateTier(itemIds, [first]);
  const updated = applySubmissionDelta(
    incrementalAggregateFrom(itemIds, baseline),
    first,
    second,
  );
  assert.deepEqual(
    {
      participants: updated.participants,
      community: updated.community,
      distributions: updated.distributions,
      disagreement: updated.disagreement,
    },
    aggregateTier(itemIds, [second]),
  );

  const deleted = applySubmissionDelta(updated, second, undefined);
  assert.equal(deleted.participants, 0);
  assert.deepEqual(deleted.community, {});
  assert.equal(deleted.distributions.a.a, 0);
  assert.equal(deleted.distributions.b.a, 0);
});

test("地域をまたぐ投票変更は旧地域を減算し、新地域へだけ加算する", () => {
  const itemIds = ["a", "b"];
  const jpVote = {s: ["a"], d: ["b"]};
  const usVote = {ss: ["b"], c: ["a"]};
  const empty = () => incrementalAggregateFrom(itemIds, undefined);

  const globalAfterFirst = applySubmissionDelta(empty(), undefined, jpVote);
  const jpAfterFirst = applySubmissionDelta(empty(), undefined, jpVote);
  const globalAfterMove = applySubmissionDelta(globalAfterFirst, jpVote, usVote);
  const jpAfterMove = applySubmissionDelta(jpAfterFirst, jpVote, undefined);
  const usAfterMove = applySubmissionDelta(empty(), undefined, usVote);

  assert.deepEqual(
    {
      participants: globalAfterMove.participants,
      community: globalAfterMove.community,
      distributions: globalAfterMove.distributions,
      disagreement: globalAfterMove.disagreement,
    },
    aggregateTier(itemIds, [usVote]),
  );
  assert.equal(jpAfterMove.participants, 0);
  assert.deepEqual(jpAfterMove.community, {});
  assert.deepEqual(
    {
      participants: usAfterMove.participants,
      community: usAfterMove.community,
      distributions: usAfterMove.distributions,
      disagreement: usAfterMove.disagreement,
    },
    aggregateTier(itemIds, [usVote]),
  );
});

test("0票・1票・大量投票の既存分布でも、1票の差分だけを更新できる", () => {
  const itemIds = ["a"];
  const empty = incrementalAggregateFrom(itemIds, undefined);
  assert.equal(empty.participants, 0);
  assert.equal(empty.distributions.a.ss, 0);

  const oneVote = {ss: ["a"]};
  const one = applySubmissionDelta(empty, undefined, oneVote);
  assert.deepEqual(
    {
      participants: one.participants,
      community: one.community,
      distributions: one.distributions,
      disagreement: one.disagreement,
    },
    aggregateTier(itemIds, [oneVote]),
  );

  const highVolume = incrementalAggregateFrom(itemIds, {
    participants: 100000,
    community: {a: "a"},
    distributions: {a: {ss: 50000, s: 50000, a: 0, b: 0, c: 0, d: 0}},
    disagreement: {a: 0.25},
  });
  const changed = applySubmissionDelta(highVolume, {s: ["a"]}, {d: ["a"]});
  assert.equal(changed.participants, 100000);
  assert.equal(changed.distributions.a.s, 49999);
  assert.equal(changed.distributions.a.d, 1);
});
