type RawReply = Record<string, unknown> & {
  id?: unknown;
  body?: unknown;
  replies?: unknown;
};

export function findReplyBody(replies: unknown, targetId: string): string | null {
  if (!Array.isArray(replies)) return null;
  for (const value of replies) {
    if (!value || typeof value !== "object") continue;
    const reply = value as RawReply;
    if (reply.id === targetId) {
      return typeof reply.body === "string" ? reply.body : "";
    }
    const nested = findReplyBody(reply.replies, targetId);
    if (nested != null) return nested;
  }
  return null;
}

export function setReplyBody(
  replies: unknown,
  targetId: string,
  body: string,
): {replies: RawReply[]; found: boolean} {
  if (!Array.isArray(replies)) return {replies: [], found: false};
  let found = false;
  const updated = replies.map((value) => {
    const reply = {...(value as RawReply)};
    if (reply.id === targetId) {
      found = true;
      return {...reply, body};
    }
    const nested = setReplyBody(reply.replies, targetId, body);
    if (nested.found) {
      found = true;
      return {...reply, replies: nested.replies};
    }
    return reply;
  });
  return {replies: updated, found};
}

function counter(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ?
    Math.max(0, Math.trunc(value)) : 0;
}

/// Transitional support for replies created before they were moved into their
/// own documents.  New replies never use this path, but it preserves old data
/// without allowing a client to rewrite its parent comment directly.
export function setLegacyReplyReaction(
  replies: unknown,
  targetId: string,
  upvotes: number,
  downvotes: number,
): {replies: RawReply[]; found: boolean} {
  if (!Array.isArray(replies)) return {replies: [], found: false};
  let found = false;
  const updated = replies.map((value) => {
    const reply = {...(value as RawReply)};
    if (reply.id === targetId) {
      found = true;
      return {...reply, upvotes: counter(upvotes), downvotes: counter(downvotes)};
    }
    const nested = setLegacyReplyReaction(
      reply.replies,
      targetId,
      upvotes,
      downvotes,
    );
    if (nested.found) {
      found = true;
      return {...reply, replies: nested.replies};
    }
    return reply;
  });
  return {replies: updated, found};
}

function collectReplyIds(reply: RawReply): string[] {
  const ids = typeof reply.id === "string" ? [reply.id] : [];
  if (!Array.isArray(reply.replies)) return ids;
  return [...ids, ...reply.replies.flatMap((child) =>
    child && typeof child === "object" ? collectReplyIds(child as RawReply) : [])];
}

export function deleteReplyTree(
  replies: unknown,
  targetId: string,
): {replies: RawReply[]; deletedIds: string[]} {
  if (!Array.isArray(replies)) return {replies: [], deletedIds: []};
  const updated: RawReply[] = [];
  let deletedIds: string[] = [];
  for (const value of replies) {
    const reply = {...(value as RawReply)};
    if (reply.id === targetId) {
      deletedIds = collectReplyIds(reply);
      continue;
    }
    const nested = deleteReplyTree(reply.replies, targetId);
    if (nested.deletedIds.length > 0) {
      deletedIds = nested.deletedIds;
      updated.push({...reply, replies: nested.replies});
    } else {
      updated.push(reply);
    }
  }
  return {replies: updated, deletedIds};
}

export function collectReplyAuthorIds(replies: unknown): string[] {
  if (!Array.isArray(replies)) return [];
  const ids = new Set<string>();
  const visit = (items: unknown[]) => {
    for (const value of items) {
      if (!value || typeof value !== "object") continue;
      const reply = value as RawReply & {authorUserId?: unknown};
      if (typeof reply.authorUserId === "string") ids.add(reply.authorUserId);
      if (Array.isArray(reply.replies)) visit(reply.replies);
    }
  };
  visit(replies);
  return [...ids];
}
