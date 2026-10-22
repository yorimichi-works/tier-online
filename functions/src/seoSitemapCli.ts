import {initializeApp} from "firebase-admin/app";

import {generateSitemapBundle} from "./seo";

async function main(): Promise<void> {
  if (!process.argv.includes("--dry-run")) {
    throw new Error("Only --dry-run is supported; sitemap delivery is dynamic and cached");
  }
  const projectArgument = process.argv.find((argument) =>
    argument.startsWith("--project="),
  );
  const projectId = projectArgument?.slice("--project=".length) ||
    process.env.SEO_SITEMAP_PROJECT_ID;
  initializeApp(projectId ? {projectId} : undefined);
  const bundle = await generateSitemapBundle();
  console.log(JSON.stringify(bundle.stats, null, 2));
}

void main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
