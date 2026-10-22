// Local only. No Firebase login, credentials, deploy command, or production project.
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { existsSync } from 'node:fs';

const root = fileURLToPath(new URL('../', import.meta.url));
const jar = process.env.FIRESTORE_EMULATOR_JAR;
if (!jar || !existsSync(jar)) {
  throw new Error('Set FIRESTORE_EMULATOR_JAR to a local Firestore emulator JAR (Java 21 required).');
}
if (!existsSync(resolve(root, 'functions/lib/accountDeletion.emulator.test.js'))) {
  throw new Error('Build existing Functions dependencies first: npm --prefix functions run build');
}
const port = 8788;
const emulator = spawn(process.env.JAVA_BIN || 'java', [
  '-jar', jar, '--host', '127.0.0.1', '--port', String(port),
  '--project_id', 'demo-tier-authorization', '--single_project_mode', 'true',
  '--rules', resolve(root, process.env.TEST_RULES_FILE || 'firestore.rules'),
], { cwd: root, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
let log = '';
emulator.stdout.on('data', (data) => { log = (log + data).slice(-16000); });
emulator.stderr.on('data', (data) => { log = (log + data).slice(-16000); });
let startupError;
const exit = new Promise((done) => {
  emulator.once('exit', (code) => done(code));
  emulator.once('error', (error) => {
    startupError = error;
    log += error.message;
    done(null);
  });
});
try {
  let ready = false;
  for (let i = 0; i < 240; i++) {
    if (startupError || emulator.exitCode !== null) throw new Error(log);
    if (log.includes('Dev App Server is now running.')) { ready = true; break; }
    await new Promise((done) => setTimeout(done, 250));
  }
  if (!ready) throw new Error(`Emulator startup timed out:\n${log}`);
  const child = spawn(process.execPath, ['--test', '--test-concurrency=1',
    ...(process.env.TEST_NAME_PATTERN ? [`--test-name-pattern=${process.env.TEST_NAME_PATTERN}`] : []),
    'test/firestore/talk_authorization.test.mjs', 'functions/lib/accountDeletion.emulator.test.js'], {
    cwd: root, stdio: 'inherit', windowsHide: true,
    env: { ...process.env, FIRESTORE_EMULATOR_HOST: `127.0.0.1:${port}` },
  });
  process.exitCode = await new Promise((done) => {
    child.once('error', () => done(1));
    child.once('exit', (code) => done(code ?? 1));
  });
  if (process.exitCode !== 0) console.error(log);
} finally {
  emulator.kill();
  await exit;
}
