import assert from "node:assert/strict";
import test from "node:test";

import {
  collectReplyAuthorIds,
  deleteReplyTree,
  findReplyBody,
  setLegacyReplyReaction,
  setReplyBody,
} from "./talkModeration";

const replies = [{
  id: "parent",
  body: "parent body",
  authorUserId: "u1",
  replies: [{id: "child", body: "child body", authorUserId: "u2"}],
}];

test("nested reply body can be hidden and restored", () => {
  assert.equal(findReplyBody(replies, "child"), "child body");
  const hidden = setReplyBody(replies, "child", "");
  assert.equal(hidden.found, true);
  assert.equal(findReplyBody(hidden.replies, "child"), "");
  assert.equal(findReplyBody(hidden.replies, "parent"), "parent body");
  const restored = setReplyBody(hidden.replies, "child", "child body");
  assert.equal(findReplyBody(restored.replies, "child"), "child body");
});

test("deleting a reply removes its subtree and author ids", () => {
  const deleted = deleteReplyTree(replies, "parent");
  assert.deepEqual(deleted.deletedIds, ["parent", "child"]);
  assert.deepEqual(deleted.replies, []);
  assert.deepEqual(collectReplyAuthorIds(deleted.replies), []);
  assert.deepEqual(collectReplyAuthorIds(replies), ["u1", "u2"]);
});

test("legacy reply reaction changes only the targeted embedded reply", () => {
  const updated = setLegacyReplyReaction(replies, "child", 4, 2);
  assert.equal(updated.found, true);
  const child = (updated.replies[0].replies as Array<{
    id: string;
    upvotes: number;
    downvotes: number;
  }>)[0];
  assert.deepEqual(
    {id: child.id, upvotes: child.upvotes, downvotes: child.downvotes},
    {id: "child", upvotes: 4, downvotes: 2},
  );
  assert.equal(setLegacyReplyReaction(replies, "missing", 1, 1).found, false);
});
