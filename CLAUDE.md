# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Maven parent POM** (no application source code) that serves as the centralized dependency management BOM for the ILM platform. Java/Spring Boot modules and connectors inherit from this POM to get standardized, pre-vetted library versions. It also owns the platform's Java **formatting and lint gates** (see below), which children likewise inherit.

- **Group ID**: `com.otilm`
- **Artifact ID**: `dependencies`
- **Parent**: Spring Boot starter parent
- **Java**: 21
- **Published to**: Maven Central Portal and GitHub Packages

## Build Commands

```bash
# Verify the POM (equivalent to CI check)
mvn -B verify -f pom.xml

# Check effective POM with all inherited dependencies resolved
mvn help:effective-pom

# Check current project version
mvn help:evaluate -Dexpression=project.version -q -DforceStdout
```

```bash
# Run once after cloning. Both gates take com.otilm:build-tools on their PLUGIN classpath, and a
# standalone goal invocation (unlike a lifecycle build) does not package it first, so `mvn
# spotless:apply` — which is what the pre-commit hook runs — cannot construct its plugin realm
# until build-tools exists in ~/.m2.
mvn -B install
```

The only Java in this repository is the `formatter-selftest` fixture set; the aggregator itself has nothing to compile. The `verify` phase validates the POM structure, smoke-tests the Checkstyle ruleset and the formatter profile, and runs JaCoCo (inherited by child projects).

## Versioning Rules

- **main branch**: Version MUST be a `-SNAPSHOT` (e.g., `1.4.1-SNAPSHOT`)
- **Tagged releases**: Version MUST NOT contain `SNAPSHOT` (e.g., `1.4.0`)
- CI enforces this: publishing will fail if the version/ref-type combination is wrong

## Maven Profiles

- **`central`**: Publishes to Maven Central Portal with GPG signing. Requires `MAVEN_GPG_PRIVATE_KEY`, `MAVEN_GPG_PASSPHRASE`, and Central Portal credentials. After deployment, releases sit in VALIDATED state until manually published in the Portal UI.
  - **Any new `packaging=jar` module must attach both a `-sources.jar` and a `-javadoc.jar`.** Central rejects the deployment if either is missing, and it does so *after* the release tag is already pushed.
- **`github`**: Publishes to GitHub Packages.

## Key Plugin Configuration (inherited by child projects)

- **Surefire** opens `java.base` modules (`java.lang`, `sun.security.rsa`, `sun.security.x509`) via `--add-opens` for security-related tests
- **Hibernate enhance** plugin enables lazy initialization bytecode enhancement
- **JaCoCo** runs coverage during the `package` phase
- **maven-jar-plugin** disables Maven descriptor in archives (`addMavenDescriptor: false`)
- **maven-compiler-plugin** enables `parameters=true` for reflection support

## Formatting and lint gates (inherited by child projects)

Two plugins, both bound to `verify`, so a child's existing CI gates on them with no workflow
changes. Their rules live in the `com.otilm:build-tools` module of this reactor and ship inside
its jar; both plugins read them off their **plugin** classpath, which is why this POM declares
`<pluginRepositories>`.

- **Spotless** (`spotless:check`) — formats `src/{main,test}/java` from
  `otilm/eclipse-formatter.xml` (Eclipse JDT engine) and `otilm/eclipse.importorder`. `mvn
  spotless:apply` fixes every violation mechanically.
- **Checkstyle** (`checkstyle:check`) — `otilm/checkstyle.xml`, exactly four rules that Spotless
  *cannot* enforce: `AvoidStarImport`, `NeedBraces`, `UnusedImports`, `RedundantImport`. These
  need hand-fixing; `spotless:apply` will not do it.
- **`.editorconfig`** is the IDE-side mirror of the Eclipse profile and must be kept in parity
  with it — the procedure is in the header of `otilm/eclipse-formatter.xml`.
- **`scripts/pre-commit.sh`** formats staged Java files before commit. It ships in the
  build-tools jar, so a child gets it installed automatically at `initialize`; `scripts/test-pre-commit.sh`
  is its test harness and runs on all three platforms in `hook-tests.yml`.
  - The install **replaces** any existing `.git/hooks/pre-commit` on every build — no chaining,
    no prompt. That is intended; `-Dgitbuildhook.install.skip=true` is the opt-out.
  - In a **linked worktree**, an antrun step in the `install-git-hooks` profile mirrors the hook
    into the common hooks dir, where Git runs it from. The `worktree-install` job in
    `hook-tests.yml` guards this.

**Keep `checkstyle.xml` to those four rules.** It exists to close Spotless's blind spots, not to
become a second linter — every rule added there is a rule 20+ repos must satisfy at once, and
unlike a formatting rule it cannot be fixed by running a command.

Escape hatches, in order of bluntness: `-Dspotless.skip=true`, `-Dcheckstyle.skip=true`,
`-Dgitbuildhook.install.skip=true`, and `git commit --no-verify` for the hook.

### Rolling the gates out to a child repo

Order matters — bumping the parent first leaves the repo red until the reformat lands, and the
IDE config has to precede any hand-fixing:

1. Copy in `.editorconfig` and `.gitattributes`. The parent POM cannot deliver these — they must
   exist in the repo before the IDE or checkout honours them. A project already open needs a reload
   to pick up a newly added `.editorconfig`.
2. `mvn spotless:apply`, then hand-fix what Checkstyle reports.
3. Commit that as a single mechanical reformat commit, touching nothing else — the two files from
   step 1 stay uncommitted for now, so this commit can be blame-ignored wholesale.
4. Record its SHA in a `.git-blame-ignore-revs` at the repo root; the `blame-ignore-revs`
   profile then wires local `git blame` to skip it automatically (GitHub's web UI does this on
   its own).
5. Commit `.editorconfig` and `.gitattributes`.
6. Only then bump `<parent>` to the version carrying the gates.

**Existing Windows worktrees need a one-time line-ending refresh.** Checkout rewrites only the
files a commit changed, so `.gitattributes` lands while the untouched files keep CRLF and
Spotless rejects them — with `git status` reporting a clean tree throughout. Affects any worktree
already holding CRLF files, including persistent Windows CI workspaces; only fresh clones and
ephemeral CI are exempt. Diagnose with `git ls-files --eol -- "*.java"` (`i/lf` vs `w/crlf`). Fix
per worktree: re-clone, or `git rm --cached -r .` followed by `git reset --hard` (discards
uncommitted changes), or `mvn spotless:apply` (covers `src/{main,test}/java` only).

## Dependency Updates

Automated via Renovate (`renovate.json`). PRs are created automatically when new dependency versions are available.

### Version overrides ahead of the parent

Most versions come from the Spring Boot parent's curated, pre-tested set — that is the value of inheriting the BOM. Occasionally a CVE hits a parent-managed library before any Spring Boot release adopts the fix; then this POM pins the fixed version ahead of the parent. Treat every such override as temporary debt with an expiry date:

- **Override only when forced.** If a published Spring Boot release already carries the fix, bump `spring-boot-starter-parent` instead — one knob, and the whole set stays tested together. Override a single library only when *no* release fixes it yet.
- **Forward-only.** An override must be `>=` the parent-managed version, never behind it.
- **Make it Renovate-visible.** A bare `<x.version>` property that only overrides a parent-managed version by name is invisible to Renovate — it has no dependency to map to, so it never gets an update PR. Back each override with an explicit `<dependency>` (or BOM `import`) in `dependencyManagement` that references `${x.version}`.
- **Document why and when it can go.** Comment each override with the driver (CVE) and the condition to remove it.
- **Undrift on every parent bump.** When bumping Spring Boot, re-audit every override: if the new parent now manages a version `>=` the override, delete the override and fall back to the parent. The vulnerability scanner will *not* flag a redundant override — it is not a vuln — so this is a manual step, not scanner-driven.
