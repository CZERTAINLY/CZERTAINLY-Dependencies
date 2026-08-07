# ILM Dependencies

> This repository is part of the commercial open source project ILM. You can find more information about the project at [ILM](https://github.com/OmniTrustILM/ilm) repository, including the contribution guide.

`Dependencies` provides the basic setting of libraries for the ILM platform in case modules or connectors are written in `Java`. There are pre-defined libraries which ILM would like to use over the modules and connectors. 

The settings are based on Spring Boot and their compliant dependencies that are regularly updated.

For more information, see [pom.xml](./pom.xml).

## Maven

`Dependencies` are available in the Maven Central Repository. To use them, add the following to your `pom.xml`:

```xml
<parent>
    <groupId>com.otilm</groupId>
    <artifactId>dependencies</artifactId>
    <version>${version}</version>
</parent>
```

## Java formatting

**Inheriting this parent also turns on two build gates that fail on badly formatted Java, so read this before bumping the version.**

Both gates run in the `verify` phase. Your existing CI already reaches that phase, so no workflow change is needed — and nothing is skipped just because you did not ask for it.

| Gate       | What it checks                                                                                   | How to fix a failure                                |
|------------|--------------------------------------------------------------------------------------------------|-----------------------------------------------------|
| Spotless   | The whole canonical style: indentation, wrapping, import order                                   | `mvn spotless:apply` fixes every violation          |
| Checkstyle | Four things Spotless cannot: `AvoidStarImport`, `NeedBraces`, `UnusedImports`, `RedundantImport` | Manually or with IDE — no command does this for you |

The rules live in the `com.otilm:build-tools` artifact, so you do not copy them into your repo. A `pre-commit` hook that formats your staged Java files is installed automatically on your first build; it ships in the same artifact.

### What the hook install does to your repo

**Every Maven build writes `.git/hooks/pre-commit`, replacing whatever is already there.** The content is the same on every build, so this is a no-op unless you keep a `pre-commit` hook of your own — and if you do, it will be overwritten without a prompt. Nothing chains it. Use `-Dgitbuildhook.install.skip=true` if you need your own hook to survive.

Hooks are not tracked by Git, so this only ever affects your machine.

Linked worktrees work: Maven mirrors the hook into the shared hooks directory that Git actually runs hooks from, because installing it into the per-worktree directory would leave it silently unused.

### Rolling it out to an existing repo

**Do the reformat first and the version bump last.** In the other order your build is red in between.

1. Bump the parent locally, without committing it.
2. Run `mvn spotless:apply`.
3. Run `mvn verify` and hand-fix what Checkstyle reports. Wildcard imports are the common one.
4. Commit the result as a single mechanical reformat commit. Change nothing else in it.
5. Create a `.git-blame-ignore-revs` at the repo root containing that commit's SHA. `git blame` then skips it, locally and in the GitHub UI.
6. Copy `.editorconfig` and `.gitattributes` from this repo. The parent POM cannot deliver these — your IDE only honours files that exist in your own repo.
7. Commit the parent bump.

### Existing Windows worktrees need a one-time refresh

**On Windows, the first build after pulling the gates fails on files the reformat never touched.** Git rewrites a file on checkout only when the commit changed it, so `.gitattributes` arrives but the untouched files keep their CRLF line endings. Spotless reads the bytes on disk and rejects them.

`git status` shows a clean tree the whole time, because the `text=auto` filter normalises CRLF on read. So there is a failing build with no Git-visible cause.

This hits any existing worktree that already contains CRLF files — commonly one created with `core.autocrlf=true`, but flipping that setting later does not rewrite files already on disk. Persistent and self-hosted Windows CI workspaces are long-lived worktrees too, so they are affected the same way. Only fresh clones and ephemeral CI runners are exempt.

Confirm it with `git ls-files --eol -- "*.java"`: an `i/lf` index entry against a `w/crlf` worktree entry is exactly the mismatch `git status` will not show you. Any one of these fixes it:

| Fix | Scope | Cost |
|-----|-------|------|
| Delete the worktree and clone again | Every file | Loses uncommitted work, stashes and local branches |
| `git rm --cached -r . && git reset --hard` | Every file | **Discards uncommitted changes** — commit or stash first |
| `mvn spotless:apply` | `src/{main,test}/java` only | Leaves other text files on CRLF |

The middle one is the usual choice. Run it once per worktree.

### When you need to opt out

| Situation                           | Escape hatch                       |
|-------------------------------------|------------------------------------|
| One build, formatting not the point | `-Dspotless.skip=true`             |
| One build, lint not the point       | `-Dcheckstyle.skip=true`           |
| You do not want the hook installed  | `-Dgitbuildhook.install.skip=true` |
| One commit, hook in the way         | `git commit --no-verify`           |

None of these change CI, which stays the authoritative gate.
