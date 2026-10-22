import assert from "node:assert/strict";
import test from "node:test";

import {replaceReplyAuthorUid} from "./anonymousAccountMigration";

test("anonymous account migration rewrites only the anonymous reply authors", () => {
  const replies = [
    {
      id: "source-root",
      authorUserId: "anonymous-uid",
      replies: [
        {id: "source-child", authorUserId: "anonymous-uid", replies: []},
        {id: "keep-child", authorUserId: "existing-uid", replies: []},
      ],
    },
    {id: "keep-root", authorUserId: "third-party", replies: []},
  ];

  const migrated = replaceReplyAuthorUid(
    replies,
    "anonymous-uid",
    "existing-uid",
  );

  assert.equal(migrated[0].authorUserId, "existing-uid");
  assert.equal(
    (migrated[0].replies as Array<{authorUserId: string}>)[0].authorUserId,
    "existing-uid",
  );
  assert.equal(
    (migrated[0].replies as Array<{authorUserId: string}>)[1].authorUserId,
    "existing-uid",
  );
  assert.equal(migrated[1].authorUserId, "third-party");
  assert.equal(replies[0].authorUserId, "anonymous-uid");
});
