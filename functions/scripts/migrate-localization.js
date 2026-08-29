const { applicationDefault, initializeApp } = require('firebase-admin/app');
const { FieldValue, getFirestore } = require('firebase-admin/firestore');

initializeApp({ credential: applicationDefault() });

const apply = process.argv.includes('--apply');
const database = getFirestore();

async function migrateCollection(name, defaults) {
  const snapshot = await database.collection(name).get();
  const changes = [];
  for (const document of snapshot.docs) {
    const data = document.data();
    const update = {};
    for (const [key, value] of Object.entries(defaults)) {
      if (data[key] === undefined || data[key] === null) {
        update[key] = typeof value === 'function' ? value(data) : value;
      }
    }
    if (Object.keys(update).length > 0) changes.push({ reference: document.ref, update });
  }

  if (apply) {
    for (let start = 0; start < changes.length; start += 400) {
      const batch = database.batch();
      for (const change of changes.slice(start, start + 400)) {
        batch.update(change.reference, {
          ...change.update,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }
  console.log(`${name}: ${changes.length} document(s) ${apply ? 'updated' : 'would be updated'}`);
}

async function main() {
  const categoryIds = {
    'ゲーム': 'games', '漫画': 'manga', 'アニメ': 'anime',
    'キャラクター': 'characters', '人物': 'people', '食べ物': 'food',
    'スポーツ': 'sports', '生活': 'lifestyle', 'ネタ': 'humor',
  };
  await migrateCollection('topics', {
    contentLanguage: 'ja',
    targetRegion: 'JP',
    categoryId: (data) => categoryIds[data.category] || 'other',
    isLanguageNeutral: false,
  });
  await migrateCollection('users', {
    preferredLocale: 'ja',
    region: 'JP',
  });
  if (!apply) console.log('Dry run only. Re-run with --apply after reviewing the counts.');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
