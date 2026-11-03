# HomerRunners

The Runners page (admins only).

## Design notes

- **Runners** (`HomerRunnersReducer`, admins only) mirrors the console's `app/(dashboard)/runners/page.tsx`: `GET /api/v1/runners` and `GET /api/v1/runners/queue`, each in its own loop on the console's 5 s (`useRunners`/`useRunnerQueue`' `refetchInterval`), so a slow queue never holds back the runners. Both are admin-only on the server (403 otherwise); the instance never shows the page, nor polls, for anyone else. A failed read keeps the last data under a banner; a 401 signs the instance out, as on every page
- **What it shows.** Stat tiles (runners, in use, external instances, pending claims with the oldest one's age), then the console's three cards: the configured runners (alias, kind, tags, in use / concurrency — `3 active` for an external runner, whose capacity is its instances'), the external runners' registered instances (only when an external runner is configured; each instance's domain is its runner's alias, which `HomerRunner` sets as it decodes them, as the console's `flatMap` does), and the claim queue grouped by what the claims wait for (`runner k8s`, `tags gpu, linux`). Beyond the console: a runner or instance with every slot taken has its capacity in orange, an instance's Last seen counts up every second (`HomerElapsedText`), and the queue's ages read `2m 5s` (`HomerFormat.duration`) where the console writes `125 s`
