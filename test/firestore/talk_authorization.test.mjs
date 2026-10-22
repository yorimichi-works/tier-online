// Exercise the actual Firestore rules over the emulator's REST API. Built-in
// Node modules only, so application dependencies/lockfiles stay unchanged.
import { before, test } from 'node:test';
import assert from 'node:assert/strict';

const host = process.env.FIRESTORE_EMULATOR_HOST;
assert.match(host || '', /^127\.0\.0\.1:\d+$/, 'A loopback emulator is mandatory');
const project = 'demo-tier-authorization';
const base = `http://${host}/v1/projects/${project}/databases/(default)/documents`;
const owner = { uid: 'alice', provider: 'password', verified: true };
const other = { uid: 'bob', provider: 'google.com', verified: true };
const anonymous = { uid: 'anonymous-user', provider: 'anonymous', verified: false };
const unverified = { uid: 'unverified', provider: 'password', verified: false };
const actors = { author: owner, other, anonymous, signedOut: null, unverified };
let sequence = 0;

// Unsigned tokens are accepted ONLY by the local emulator. They are fixtures,
// not server credentials and cannot authenticate against production Firebase.
function mockToken(actor) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({ alg: 'none', typ: 'JWT' })}.${encode({
    sub: actor.uid, user_id: actor.uid, aud: project,
    iss: `https://securetoken.google.com/${project}`,
    iat: 0, exp: 4102444800, email_verified: actor.verified,
    firebase: { sign_in_provider: actor.provider, identities: {} },
  })}.`;
}
function value(data) {
  if (data === null) return { nullValue: null };
  if (typeof data === 'string') return { stringValue: data };
  if (typeof data === 'boolean') return { booleanValue: data };
  if (typeof data === 'number') return Number.isInteger(data)
    ? { integerValue: String(data) } : { doubleValue: data };
  if (Array.isArray(data)) return { arrayValue: { values: data.map(value) } };
  return { mapValue: { fields: fields(data) } };
}
const fields = (data) => Object.fromEntries(Object.entries(data).map(([k, v]) => [k, value(v)]));
async function request(method, path, data, actor, mask, legacyClient = false) {
  if (method === 'PATCH' && actor !== 'seed' && path.startsWith('topics/') && !legacyClient) {
    data = { ...data, clientProtocolVersion: 2, clientBuild: 2 };
    if (mask) mask = [...mask, 'clientProtocolVersion', 'clientBuild'];
  }
  const params = new URLSearchParams();
  for (const key of mask || []) params.append('updateMask.fieldPaths', key);
  const token = actor === 'seed' ? 'owner' : actor ? mockToken(actor) : null;
  const response = await fetch(`${base}/${path}?${params}`, {
    method, headers: { 'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    ...(data ? { body: JSON.stringify({ fields: fields(data) }) } : {}),
  });
  return { status: response.status, data: await response.json() };
}
async function allowed(result) {
  const response = await result;
  assert.ok(response.status >= 200 && response.status < 300, JSON.stringify(response));
  return response.data;
}
async function denied(result) {
  const response = await result;
  assert.equal(response.status, 403, JSON.stringify(response));
}
const post = (uid = 'alice', extra = {}) => ({
  id: 'post', author: 'display name', authorUserId: uid, body: 'original body',
  rank: 's', minutesAgo: 0, createdAt: '2026-10-22T00:00:00.000Z',
  attachedTier: false, replies: [], upvotes: 0, downvotes: 0, ...extra,
});
const reply = (id, uid = 'alice', extra = {}) => ({
  id, author: 'reply name', authorUserId: uid, body: 'reply body',
  createdAt: '2026-10-22T00:00:00.000Z', stance: null, parentReplyId: null,
  replies: [], upvotes: 0, downvotes: 0, ...extra,
});
const path = (topic, tail = '') => `topics/${topic}/talks/post${tail}`;

before(async () => {
  // Never clear/import an existing emulator database. This runner starts a
  // separate ephemeral process and seeds only its fixed demo project.
  await allowed(request('PATCH', 'clientPolicies/talks', {
    writesEnabled: true, readProtocolVersion: 2, minProtocolVersion: 2, minClientBuild: 2,
  }, 'seed'));
  for (const topic of ['public', 'private']) {
    await allowed(request('PATCH', `topics/${topic}`, {
      creatorId: 'alice', isPublic: topic === 'public',
    }, 'seed'));
    await allowed(request('PATCH', path(topic), post(), 'seed'));
    await allowed(request('PATCH', path(topic, '/replies/existing'), reply('existing'), 'seed'));
    await allowed(request('PATCH', path(topic, '/reactions/alice'), {
      userId: 'alice', votes: { root: 'up', existing: 'down' },
    }, 'seed'));
    const legacy = post(undefined, { id: 'legacy', upvotes: 7, downvotes: 2,
      replies: [reply('legacy-reply', undefined, { replies: [reply('nested-legacy')] })],
      replyAuthorIds: ['alice'], customPreserved: 'keep me',
    });
    delete legacy.authorUserId;
    delete legacy.replies[0].authorUserId;
    await allowed(request('PATCH', `topics/${topic}/talks/legacy`, legacy, 'seed'));
  }
});

test('legacy whole-document clients are gated while v2 can edit a UID-owned legacy body', async () => {
  const legacy = post('alice', { id: 'compat-legacy', upvotes: 7,
    replies: [reply('old-reply', 'bob')] });
  const target = 'topics/public/talks/compat-legacy';
  await allowed(request('PATCH', target, legacy, 'seed'));
  await denied(request('PATCH', target, { ...legacy, body: 'old whole replacement' }, owner, undefined, true));
  await allowed(request('PATCH', target, { body: 'v2 author edit' }, owner, ['body']));
  const saved = await allowed(request('GET', target, null, owner));
  assert.equal(saved.fields.upvotes.integerValue, '7');
  assert.equal(saved.fields.replies.arrayValue.values.length, 1);
  assert.equal(saved.fields.authorUserId.stringValue, 'alice');
  await denied(request('DELETE', target, null, owner));
  await denied(request('DELETE', path('public', '/replies/existing'), null, owner));
});

test('the compatibility policy is readable but never client writable', async () => {
  for (const actor of Object.values(actors)) {
    await allowed(request('GET', 'clientPolicies/talks', null, actor));
    await denied(request('PATCH', 'clientPolicies/talks', { writesEnabled: true }, actor));
    await denied(request('DELETE', 'clientPolicies/talks', null, actor));
  }
});

test('pausing or raising the required build blocks writes while old and new activity stay readable', async () => {
  const target = 'topics/public/talks/rollout';
  await allowed(request('PATCH', target, post('alice', { id: 'rollout', upvotes: 7,
    replies: [reply('embedded', 'bob')] }), 'seed'));
  await allowed(request('PATCH', `${target}/replies/separate`, reply('separate', 'bob'), other));
  for (const policy of [
    { writesEnabled: false, readProtocolVersion: 2, minProtocolVersion: 2, minClientBuild: 2 },
    { writesEnabled: true, readProtocolVersion: 2, minProtocolVersion: 2, minClientBuild: 3 },
    { writesEnabled: true, readProtocolVersion: 2, minProtocolVersion: 3, minClientBuild: 2 },
  ]) {
    await allowed(request('PATCH', 'clientPolicies/talks', policy, 'seed'));
    await denied(request('PATCH', `${target}/replies/blocked`, reply('blocked', 'bob'), other));
    await denied(request('PATCH', `${target}/reactions/bob`, { userId: 'bob', votes: { root: 'up' } }, other));
    const saved = await allowed(request('GET', target, null, null));
    assert.equal(saved.fields.upvotes.integerValue, '7');
    assert.equal(saved.fields.replies.arrayValue.values.length, 1);
    await allowed(request('GET', `${target}/replies/separate`, null, null));
  }
  await allowed(request('PATCH', 'clientPolicies/talks', {
    writesEnabled: true, readProtocolVersion: 2, minProtocolVersion: 2, minClientBuild: 2,
  }, 'seed'));
});

test('a missing or malformed rollout policy fails closed', async () => {
  await allowed(request('DELETE', 'clientPolicies/talks', null, 'seed'));
  await denied(request('PATCH', path('public', '/reactions/bob'), { userId: 'bob', votes: { root: 'up' } }, other));
  await allowed(request('PATCH', 'clientPolicies/talks', { writesEnabled: true }, 'seed'));
  await denied(request('PATCH', path('public', '/reactions/bob'), { userId: 'bob', votes: { root: 'up' } }, other));
  await allowed(request('PATCH', 'clientPolicies/talks', {
    writesEnabled: true, readProtocolVersion: 2, minProtocolVersion: 2, minClientBuild: 2,
  }, 'seed'));
});

for (const topic of ['public', 'private']) {
  for (const [name, actor] of Object.entries(actors)) {
    const view = topic === 'public' || name === 'author';
    const participate = view && actor && name !== 'unverified';
    const check = participate ? allowed : denied;
    test(`${topic}/${name}: read post/replies/reactions`, async () => {
      const read = view ? allowed : denied;
      await read(request('GET', path(topic), null, actor));
      await read(request('GET', path(topic, '/replies'), null, actor));
      await read(request('GET', path(topic, '/reactions'), null, actor));
    });
    test(`${topic}/${name}: create own post, reject forged/missing UID and preloaded activity`, async () => {
      const id = `new-${++sequence}`;
      const createPath = `topics/${topic}/talks/${id}`;
      await check(request('PATCH', createPath, post(actor?.uid, { id }), actor));
      if (participate) {
        await allowed(request('PATCH', createPath, { body: 'own post edit' }, actor, ['body']));
      }
      await denied(request('PATCH', `${createPath}-forged`, post('victim', { id: `${id}-forged` }), actor));
      const missing = post(undefined, { id: `${id}-missing` }); delete missing.authorUserId;
      await denied(request('PATCH', `${createPath}-missing`, missing, actor));
      for (const extra of [{ upvotes: 100 }, { downvotes: 100 },
        { replies: [reply('forged', 'victim')] }, { replyAuthorIds: ['victim'] }]) {
        const badId = `bad-${++sequence}`;
        await denied(request('PATCH', `topics/${topic}/talks/${badId}`,
          post(actor?.uid, { id: badId, ...extra }), actor));
      }
    });
    test(`${topic}/${name}: body author only; identity/embedded replies/counters immutable`, async () => {
      await (participate && name === 'author' ? allowed : denied)(
        request('PATCH', path(topic), { body: 'author edit' }, actor, ['body']));
      for (const [key, data] of Object.entries({ authorUserId: actor?.uid || 'victim',
        author: 'impersonated name', rank: 'd', attachedTier: true,
        createdAt: 'different', replies: [reply('bad')], upvotes: 999, downvotes: 999,
        replyAuthorIds: ['victim'], futureSecurityField: true })) {
        // Set an actually different UID even when the actor is the author.
        await denied(request('PATCH', path(topic), { [key]: key === 'authorUserId' ? 'victim' : data }, actor, [key]));
      }
      await denied(request('PATCH', path(topic), {}, actor, ['authorUserId']));
    });
    test(`${topic}/${name}: add own/nested reply; cannot overwrite another reply`, async () => {
      const id = `reply-${++sequence}`;
      await check(request('PATCH', path(topic, `/replies/${id}`), reply(id, actor?.uid), actor));
      if (participate) {
        await allowed(request('PATCH', path(topic, `/replies/${id}`), { body: 'own reply edit' }, actor, ['body']));
      }
      const nestedId = `reply-${++sequence}`;
      await check(request('PATCH', path(topic, `/replies/${nestedId}`),
        reply(nestedId, actor?.uid, { parentReplyId: 'existing' }), actor));
      const forged = `reply-${++sequence}`;
      await denied(request('PATCH', path(topic, `/replies/${forged}`), reply(forged, 'victim'), actor));
      await (participate && name === 'author' ? allowed : denied)(
        request('PATCH', path(topic, '/replies/existing'), { body: 'edited reply' }, actor, ['body']));
      for (const [key, data] of Object.entries({ authorUserId: 'victim', author: 'forged',
        parentReplyId: 'elsewhere', replies: [reply('nested-forged', 'victim')], upvotes: 100, downvotes: 100 })) {
        await denied(request('PATCH', path(topic, '/replies/existing'), { [key]: data }, actor, [key]));
      }
    });
    test(`${topic}/${name}: own root/reply reactions, switch and remove; no other user's choices`, async () => {
      const uid = actor?.uid || 'signed-out';
      const own = path(topic, `/reactions/${uid}`);
      await check(request('PATCH', own, { userId: uid, votes: { root: 'up', existing: 'down' } }, actor));
      await check(request('PATCH', own, { userId: uid, votes: { root: 'down' } }, actor));
      await check(request('PATCH', own, { userId: uid, votes: {} }, actor));
      await denied(request('PATCH', path(topic, '/reactions/victim'), { userId: 'victim', votes: { root: 'up' } }, actor));
      await denied(request('PATCH', own, { userId: 'victim', votes: { root: 'up' } }, actor));
      await denied(request('PATCH', own, { userId: uid, votes: { root: 100 } }, actor));
      await denied(request('PATCH', own, { userId: uid, votes: { root: 'up' }, body: 'smuggled' }, actor));
      await denied(request('DELETE', path(topic, '/reactions/victim'), null, actor));
      await check(request('DELETE', own, null, actor));
    });
    test(`${topic}/${name}: ownerless legacy content frozen, new replies/reactions work`, async () => {
      const legacyPath = `topics/${topic}/talks/legacy`;
      await (view ? allowed : denied)(request('GET', legacyPath, null, actor));
      await denied(request('PATCH', legacyPath, { body: 'takeover' }, actor, ['body']));
      await denied(request('PATCH', legacyPath, { authorUserId: actor?.uid || 'victim' }, actor, ['authorUserId']));
      await denied(request('PATCH', legacyPath, { replies: [] }, actor, ['replies']));
      const id = `reply-${++sequence}`;
      await check(request('PATCH', `${legacyPath}/replies/${id}`,
        reply(id, actor?.uid, { parentReplyId: 'legacy-reply' }), actor));
      await check(request('PATCH', `${legacyPath}/reactions/${actor?.uid || 'signed-out'}`,
        { userId: actor?.uid || 'signed-out', votes: { root: 'up', 'legacy-reply': 'down' } }, actor));
    });
  }
}

test('a former author cannot edit a now-private topic owned by someone else', async () => {
  await allowed(request('PATCH', 'topics/private/talks/former-post', post('bob', { id: 'former-post' }), 'seed'));
  await denied(request('PATCH', 'topics/private/talks/former-post', { body: 'no longer visible' }, other, ['body']));
  await allowed(request('PATCH', path('private', '/replies/former-author'), reply('former-author', 'bob'), 'seed'));
  await denied(request('PATCH', path('private', '/replies/former-author'), { body: 'no longer visible' }, other, ['body']));
});

test('an anonymous topic owner can participate in their own private topic', async () => {
  await allowed(request('PATCH', 'topics/private-anonymous', {
    creatorId: anonymous.uid, isPublic: false,
  }, 'seed'));
  const ownPost = 'topics/private-anonymous/talks/post';
  await allowed(request('PATCH', ownPost, post(anonymous.uid), anonymous));
  await allowed(request('PATCH', ownPost, { body: 'own edit' }, anonymous, ['body']));
  await allowed(request('PATCH', `${ownPost}/replies/own-reply`, reply('own-reply', anonymous.uid), anonymous));
  await allowed(request('PATCH', `${ownPost}/reactions/${anonymous.uid}`, {
    userId: anonymous.uid, votes: { root: 'up', 'own-reply': 'down' },
  }, anonymous));
  await denied(request('GET', ownPost, null, owner));
});
test('missing parents deny replies/reactions and public reads do not bypass parent visibility', async () => {
  for (const suffix of ['replies/orphan', 'reactions/bob']) {
    await denied(request('PATCH', `topics/public/talks/missing/${suffix}`,
      suffix.startsWith('replies') ? reply('orphan', 'bob') : { userId: 'bob', votes: { root: 'up' } }, other));
  }
  await denied(request('PATCH', 'topics/missing/talks/post', post(), owner));
});
test('legacy documents including nested replies/custom fields/counters remain intact', async () => {
  for (const topic of ['public', 'private']) {
    const saved = await allowed(request('GET', `topics/${topic}/talks/legacy`, null, 'seed'));
    assert.equal(saved.fields.authorUserId, undefined);
    assert.equal(saved.fields.body.stringValue, 'original body');
    assert.equal(saved.fields.upvotes.integerValue, '7');
    assert.equal(saved.fields.downvotes.integerValue, '2');
    assert.equal(saved.fields.customPreserved.stringValue, 'keep me');
    const embedded = saved.fields.replies.arrayValue.values[0].mapValue.fields;
    assert.equal(embedded.authorUserId, undefined);
    assert.equal(embedded.replies.arrayValue.values.length, 1);
  }
});

test('malformed content and reaction payloads are rejected', async () => {
  for (const extra of [{ rank: 1 }, { rank: 'invalid' }, { body: null }, { author: 123 },
    { createdAt: 'not a date' }, { minutesAgo: '0' }, { attachedTier: 'true' }, { upvotes: 0.1 }]) {
    const id = `invalid-${++sequence}`;
    await denied(request('PATCH', `topics/public/talks/${id}`, post('alice', { id, ...extra }), owner));
  }
  for (const extra of [{ createdAt: null }, { createdAt: 'invalid' }, { stance: 'invalid' },
    { body: 123 }, { replies: [reply('smuggled')] }, { upvotes: 3 }]) {
    const id = `invalid-reply-${++sequence}`;
    await denied(request('PATCH', path('public', `/replies/${id}`), reply(id, 'alice', extra), owner));
  }
  for (const payload of [{}, { userId: 'alice' }, { userId: 'alice', votes: [] },
    { userId: 'alice', votes: { root: 'invalid' } },
    { userId: 'alice', votes: Object.fromEntries(Array.from({ length: 1001 }, (_, i) => [`reply-${i}`, 'up'])) }]) {
    await denied(request('PATCH', path('public', '/reactions/alice'), payload, owner));
  }
});

test('a stale full-parent batch cannot smuggle body/reply/counter changes; the batch is atomic', async () => {
  const before = await allowed(request('GET', path('public'), null, 'seed'));
  const forged = post('alice', { body: 'forged body', upvotes: 999,
    replies: [reply('forged', 'alice')] });
  const response = await fetch(`${base}:commit`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${mockToken(other)}` },
    body: JSON.stringify({ writes: [
      { update: { name: `projects/${project}/databases/(default)/documents/${path('public')}`, fields: fields(forged) } },
      { update: { name: `projects/${project}/databases/(default)/documents/${path('public', '/replies/batch-reply')}`,
        fields: fields(reply('batch-reply', 'bob')) } },
    ] }),
  });
  assert.equal(response.status, 403, await response.text());
  const after = await allowed(request('GET', path('public'), null, 'seed'));
  assert.deepEqual(after.fields, before.fields);
  assert.equal((await request('GET', path('public', '/replies/batch-reply'), null, 'seed')).status, 404);
});
