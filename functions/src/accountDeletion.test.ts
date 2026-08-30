import assert from "node:assert/strict";
import test from "node:test";

import {collectReplyAuthorIds, removeRepliesByAuthor} from "./accountDeletion";

test("account deletion removes authored replies at every nesting level", () => {
  const replies = [
    {
      id: "keep",
      authorUserId: "other",
      replies: [
        {id: "remove-child", authorUserId: "target", replies: []},
        {
          id: "keep-child",
          authorUserId: "another",
          replies: [{id: "remove-deep", authorUserId: "target", replies: []}],
        },
      ],
    },
    {id: "remove-root", authorUserId: "target", replies: []},
  ];

  const filtered = removeRepliesByAuthor(replies, "target");
  assert.deepEqual(filtered, [{
    id: "keep",
    authorUserId: "other",
    replies: [{
      id: "keep-child",
      authorUserId: "another",
      replies: [],
    }],
  }]);
  assert.deepEqual(collectReplyAuthorIds(filtered).sort(), ["another", "other"]);
});
