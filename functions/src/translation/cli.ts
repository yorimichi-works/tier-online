import {mkdir, readFile, writeFile} from "node:fs/promises";
import {dirname, resolve} from "node:path";

import {
  createBatchId,
  fetchAndClaimPending,
  importTranslatedBatch,
  initializeTranslationFirestore,
  resetStaleProcessing,
} from "./firestoreBatch";
import {
  SourceBatch,
  TranslatedBatch,
  validateTranslatedBatch,
} from "./translationBatch";

type Flags = Record<string, string | boolean>;

const parseFlags = (args: string[]): Flags => {
  const result: Flags = {};
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (!argument.startsWith("--")) continue;
    const key = argument.slice(2);
    const next = args[index + 1];
    if (next && !next.startsWith("--")) {
      result[key] = next;
      index += 1;
    } else {
      result[key] = true;
    }
  }
  return result;
};

const stringFlag = (flags: Flags, name: string): string | undefined => {
  const value = flags[name];
  return typeof value === "string" ? value : undefined;
};

const positiveInteger = (
  flags: Flags,
  name: string,
  fallback: number,
): number => {
  const value = Number(stringFlag(flags, name) ?? fallback);
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`--${name} must be a positive integer`);
  }
  return value;
};

const readJson = async <T>(path: string): Promise<T> =>
  JSON.parse(await readFile(resolve(path), "utf8")) as T;

const writeJson = async (path: string, value: unknown) => {
  const absolute = resolve(path);
  await mkdir(dirname(absolute), {recursive: true});
  await writeFile(absolute, `${JSON.stringify(value, null, 2)}\n`, "utf8");
};

const requireProject = (flags: Flags): string => {
  const project = stringFlag(flags, "project");
  if (!project) throw new Error("--project is required");
  return project;
};

const confirmWriteProject = (flags: Flags, project: string) => {
  if (flags["dry-run"] === true) return;
  if (stringFlag(flags, "confirm-project") !== project) {
    throw new Error(
      `Write blocked. Pass --confirm-project ${project} after verifying the target.`,
    );
  }
};

const usage = `
Translation batch commands:
  fetch --project ID --confirm-project ID [--batch-size 100] [--output PATH]
  validate --source PATH --translated PATH [--output PATH]
  import --project ID --source PATH --translated PATH --dry-run
  import --project ID --confirm-project ID --source PATH --translated PATH
  reset-stale --project ID --dry-run [--stale-hours 24]
  reset-stale --project ID --confirm-project ID [--stale-hours 24]
`;

const repositoryRoot = resolve(__dirname, "..", "..", "..");

export const runCli = async (args = process.argv.slice(2)): Promise<void> => {
  const [command, ...rest] = args;
  const flags = parseFlags(rest);
  if (!command || command === "help" || flags.help === true) {
    console.log(usage.trim());
    return;
  }

  if (command === "validate") {
    const sourcePath = stringFlag(flags, "source");
    const translatedPath = stringFlag(flags, "translated");
    if (!sourcePath || !translatedPath) {
      throw new Error("validate requires --source and --translated");
    }
    const source = await readJson<SourceBatch>(sourcePath);
    const translated = await readJson<unknown>(translatedPath);
    const report = validateTranslatedBatch(source, translated);
    const output = stringFlag(flags, "output") ??
      resolve(dirname(resolve(translatedPath)), "validation.json");
    await writeJson(output, report);
    console.log(JSON.stringify({...report, output}, null, 2));
    if (!report.valid) process.exitCode = 1;
    return;
  }

  const project = requireProject(flags);
  const firestore = initializeTranslationFirestore(project);
  if (command === "fetch") {
    confirmWriteProject(flags, project);
    const batchId = stringFlag(flags, "batch-id") ?? createBatchId();
    const batchSize = positiveInteger(
      flags,
      "batch-size",
      Number(process.env.TRANSLATION_BATCH_SIZE ?? 100),
    );
    const scanLimit = positiveInteger(
      flags,
      "scan-limit",
      Math.max(batchSize * 10, batchSize),
    );
    const output = stringFlag(flags, "output") ??
      resolve(repositoryRoot, "tmp", "translations", batchId, "source.json");
    const batch = await fetchAndClaimPending(firestore, {
      batchId,
      batchSize,
      scanLimit,
      dryRun: flags["dry-run"] === true,
    });
    await writeJson(output, batch);
    console.log(JSON.stringify({
      batchId,
      itemCount: batch.items.length,
      output,
      dryRun: flags["dry-run"] === true,
      message: batch.items.length === 0 ? "No pending translations." : undefined,
    }, null, 2));
    return;
  }

  if (command === "import") {
    const sourcePath = stringFlag(flags, "source");
    const translatedPath = stringFlag(flags, "translated");
    if (!sourcePath || !translatedPath) {
      throw new Error("import requires --source and --translated");
    }
    confirmWriteProject(flags, project);
    const source = await readJson<SourceBatch>(sourcePath);
    const translated = await readJson<TranslatedBatch>(translatedPath);
    const report = await importTranslatedBatch(
      firestore,
      source,
      translated,
      flags["dry-run"] === true,
    );
    console.log(JSON.stringify(report, null, 2));
    return;
  }

  if (command === "reset-stale") {
    confirmWriteProject(flags, project);
    const staleHours = positiveInteger(
      flags,
      "stale-hours",
      Number(process.env.TRANSLATION_STALE_HOURS ?? 24),
    );
    const reset = await resetStaleProcessing(
      firestore,
      staleHours,
      flags["dry-run"] === true,
    );
    console.log(JSON.stringify({
      staleHours,
      dryRun: flags["dry-run"] === true,
      resetCount: reset.length,
      documentIds: reset,
    }, null, 2));
    return;
  }

  throw new Error(`Unknown command: ${command}\n${usage}`);
};

if (require.main === module) {
  runCli().catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  });
}
