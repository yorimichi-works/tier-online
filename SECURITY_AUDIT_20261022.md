# Security dependency audit — 2026-10-22

Base: `main` at `8cb05ecacda9d4572e4cd164687f6d7729ef5d68`. Work branch: `fix/security-audit-20261022`.

Existing developer checkouts, uncommitted changes, data, and binary assets were left untouched. This separate sparse checkout contains code and text configuration. Images and LFS assets were not fetched. No merge, deployment, store submission, or access-control change was performed.

## Dependency changes

| Package | Before | After |
|---|---|---|
| proxy-addr | 2.0.7 | 2.0.8 |
| @grpc/grpc-js | 1.14.4 | 1.14.6 |
| brace-expansion | 2.1.4 | 2.1.7 |
| qs | 6.15.3 | 6.16.1 |

## Verification

Portable, SHA256-verified official Node.js 22.23.4 was used. The development pin is in .nvmrc. Production Node patch levels are unverified; the engines major is not proof of a patched deployed runtime.

| Check | Latest result | Seconds |
|---|---|---|
| ci | PASS | 125 |
| test | PASS | 30 |

## Remaining findings and limits

The final OSV query found no match among the targeted public npm package/version pairs in this lockfile. This was a targeted check, not proof that every dependency or application behavior is free of vulnerabilities.

The proxy-addr advisory requires a relevant trusted-proxy/subnet configuration; no deployed trust configuration or runtime patch level was verified here. The dependency version was patched independently of that reachability question.

Shipping status: changes on this work branch are not deployed, and no claim is made that the distributed app has received these fixes. Unity editor and Firestore/Storage rules are outside this change.

## Primary references

- [React RSC advisory](https://github.com/react/react/security/advisories/GHSA-xqc2-xf4c-x3h3)
- [sharp/librsvg advisory](https://github.com/advisories/GHSA-wq5f-xc86-pv6w)
- [Satori serialization release](https://github.com/vercel/satori/releases/tag/0.33.5)
- [Vite advisories](https://github.com/advisories/GHSA-rq7h-c2jc-7f22)
- [Node October security releases](https://nodejs.org/en/blog/vulnerability/october-2026-security-releases)
