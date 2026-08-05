#!/usr/bin/env bash
# Test harness for scripts/pre-commit.sh.
#
# Self-contained: builds throwaway git repos in a temp directory and puts a stub
# `mvn` on PATH, so no JDK, no Maven and no network are needed. The stub mimics
# the one behaviour of spotless-maven-plugin the hook depends on -- it reports
# how many files its -DspotlessFiles regex matched -- which is what lets the
# no-op detection be tested at all.
#
# Usage:
#   scripts/test-pre-commit.sh              # test with the bash on PATH
#   TEST_BASH=/bin/bash scripts/test-pre-commit.sh
#
# This harness must itself stay bash 3.2 compatible; it is run under 3.2 in CI.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="$HERE/pre-commit.sh"
# Resolved to an absolute path: one case below runs the hook with a PATH that
# deliberately contains nothing but git, and a bare "bash" would not be found.
TEST_BASH=$(command -v "${TEST_BASH:-bash}") || {
    echo "no bash found for TEST_BASH=${TEST_BASH:-bash}" >&2
    exit 1
}

[ -f "$HOOK" ] || {
    echo "no hook at $HOOK" >&2
    exit 1
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/pre-commit-tests-XXXXXX")
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
FAILED_CASES=''

# --- assertions ---------------------------------------------------------------

ok() {
    PASS=$((PASS + 1))
    printf '    ok   %s\n' "$1"
}

no() {
    FAIL=$((FAIL + 1))
    FAILED_CASES="$FAILED_CASES
  - $CASE: $1"
    printf '    FAIL %s\n' "$1"
}

assert_contains() { # haystack-file needle label
    if grep -qF -- "$2" "$1" 2>/dev/null; then ok "$3"; else
        no "$3 (missing: $2)"
    fi
}

assert_not_contains() { # haystack-file needle label
    if grep -qF -- "$2" "$1" 2>/dev/null; then
        no "$3 (unexpectedly present: $2)"
    else ok "$3"; fi
}

assert_eq() { # actual expected label
    if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (got '$1', want '$2')"; fi
}

# --- fixtures ----------------------------------------------------------------

# The stub records its argv, emulates the plugin's \Q..\E unquoting, "formats"
# each file it matched by deleting UNFORMATTED lines, and prints the count line.
# STUB_MODE: normal | noop (print no count line) | partial (undercount) | fail |
# winpath (treat the pattern as a Windows path, the way a JVM on Windows would).
write_stub_mvn() {
    cat >"$1/mvn" <<'STUB'
#!/usr/bin/env bash
set -f
printf '%s\n' "$*" >> "$STUB_LOG"
printf 'MSYS2_ARG_CONV_EXCL=%s\n' "${MSYS2_ARG_CONV_EXCL:-unset}" >> "$STUB_LOG"
mode=${STUB_MODE:-normal}
if [ "$mode" = fail ]; then echo "[ERROR] stub maven failure"; exit 1; fi
pat=''
for a in "$@"; do
    case $a in -DspotlessFiles=*) pat=${a#-DspotlessFiles=} ;; esac
done
n=0
oldifs=$IFS
IFS=','
for p in $pat; do
    IFS=$oldifs
    q=${p#'\Q'}; q=${q%'\E'}
    # A JVM on Windows resolves "C:\a\b"; this test filesystem holds "/a/b".
    if [ "$mode" = winpath ]; then
        case $q in
            [A-Za-z]:\\*) q=$(printf '%s' "$q" | sed -e 's|^[A-Za-z]:||' -e 's|\\|/|g') ;;
        esac
    fi
    if [ -f "$q" ]; then
        n=$((n + 1))
        grep -v 'UNFORMATTED' "$q" > "$q.stub" 2>/dev/null || true
        mv "$q.stub" "$q"
    fi
    IFS=','
done
IFS=$oldifs
case $mode in
    noop) ;;
    partial) echo "[INFO] Spotless.Java is keeping $((n > 1 ? n - 1 : 0)) files clean - 0 were changed to be clean" ;;
    *) echo "[INFO] Spotless.Java is keeping $n files clean - $n were changed to be clean, 0 were already clean, 0 were skipped" ;;
esac
exit 0
STUB
    chmod +x "$1/mvn"
}

# A fresh repo with the hook available. Sets: REPO, BIN, STUB_LOG.
new_repo() {
    REPO="$WORK/$CASE"
    BIN="$REPO/.bin"
    STUB_LOG="$REPO/.mvn-argv"
    mkdir -p "$REPO" "$BIN"
    : >"$STUB_LOG"
    write_stub_mvn "$BIN"
    (
        cd "$REPO" || exit 1
        git init -q .
        git config user.email t@example.com
        git config user.name Test
        git config commit.gpgsign false
        git config core.hooksPath .git/hooks
    )
}

java_file() { # path marker
    mkdir -p "$REPO/$(dirname "$1")"
    printf 'package p;\nclass C { }\n%s\n' "${2:-}" >"$REPO/$1"
}

# Run the hook the way git would, but under $TEST_BASH. Sets HOOK_RC, HOOK_OUT.
run_hook() {
    HOOK_OUT="$REPO/.hook-out"
    (
        cd "$REPO" || exit 1
        PATH="$BIN:$PATH" STUB_LOG="$STUB_LOG" STUB_MODE="${STUB_MODE:-normal}" \
            "$TEST_BASH" "$HOOK" >"$HOOK_OUT" 2>&1
    )
    HOOK_RC=$?
}

staged_content() { # path -> stdout
    (cd "$REPO" && git show ":$1" 2>/dev/null)
}

begin() {
    CASE="$1"
    STUB_MODE=normal
    printf '\n== %s\n' "$1"
    new_repo
}

# --- cases -------------------------------------------------------------------

begin no_java_staged
echo hi >"$REPO/notes.txt"
(cd "$REPO" && git add notes.txt)
run_hook
assert_eq "$HOOK_RC" 0 'exits 0'
assert_eq "$(wc -l <"$STUB_LOG" | tr -d ' ')" 0 'never invokes maven'

begin nothing_staged
run_hook
assert_eq "$HOOK_RC" 0 'exits 0 on an empty index'

begin formats_and_restages
java_file src/main/java/A.java UNFORMATTED
(cd "$REPO" && git add src/main/java/A.java)
run_hook
assert_eq "$HOOK_RC" 0 'exits 0'
staged_content src/main/java/A.java >"$REPO/.idx"
assert_not_contains "$REPO/.idx" UNFORMATTED 'index holds the formatted content'
assert_not_contains "$REPO/src/main/java/A.java" UNFORMATTED 'worktree holds the formatted content'

# The blocker: a file staged in part must not have its unstaged remainder swept in.
begin preserves_unstaged_changes
java_file src/main/java/A.java UNFORMATTED
(
    cd "$REPO" && git add src/main/java/A.java && git commit -qm init --no-verify
    printf 'package p;\nclass C { }\nUNFORMATTED\nSTAGED_EDIT\n' >src/main/java/A.java
    git add src/main/java/A.java
    printf 'package p;\nclass C { }\nUNFORMATTED\nSTAGED_EDIT\nSECRET_UNSTAGED\n' >src/main/java/A.java
)
run_hook
assert_eq "$HOOK_RC" 0 'exits 0'
staged_content src/main/java/A.java >"$REPO/.idx"
assert_not_contains "$REPO/.idx" SECRET_UNSTAGED 'unstaged line stays OUT of the index'
assert_contains "$REPO/src/main/java/A.java" SECRET_UNSTAGED 'unstaged line survives in the worktree'
assert_contains "$HOOK_OUT" 'unstaged changes' 'warns about the partially staged file'
assert_eq "$(wc -l <"$STUB_LOG" | tr -d ' ')" 0 'does not ask maven to format it'

begin mixed_clean_and_partial
java_file src/main/java/Clean.java UNFORMATTED
java_file src/main/java/Partial.java UNFORMATTED
(
    cd "$REPO" && git add . && git commit -qm init --no-verify
    printf 'package p;\nclass C { }\nUNFORMATTED\nx\n' >src/main/java/Clean.java
    printf 'package p;\nclass C { }\nUNFORMATTED\ny\n' >src/main/java/Partial.java
    git add src/main/java/Clean.java src/main/java/Partial.java
    printf 'package p;\nclass C { }\nUNFORMATTED\ny\nEXTRA\n' >src/main/java/Partial.java
)
run_hook
assert_eq "$HOOK_RC" 0 'exits 0'
staged_content src/main/java/Clean.java >"$REPO/.c"
staged_content src/main/java/Partial.java >"$REPO/.p"
assert_not_contains "$REPO/.c" UNFORMATTED 'clean file is formatted'
assert_contains "$REPO/.p" UNFORMATTED 'partial file is left alone'
assert_not_contains "$REPO/.p" EXTRA 'partial file keeps its unstaged line out of the index'

# Regex metacharacters and spaces in the path: the silent-no-op class of bug.
begin path_with_metachars
java_file 'src/main/java/weird (x86)+dir/A.java' UNFORMATTED
(cd "$REPO" && git add .)
run_hook
assert_eq "$HOOK_RC" 0 'exits 0'
assert_contains "$STUB_LOG" '\Q' 'passes a regex-quoted pattern'
assert_contains "$STUB_LOG" 'weird (x86)+dir' 'pattern carries the literal directory name'
assert_not_contains "$REPO/src/main/java/weird (x86)+dir/A.java" UNFORMATTED 'file with metachars is formatted'

begin filename_with_spaces
java_file 'src/main/java/My Class.java' UNFORMATTED
(cd "$REPO" && git add .)
run_hook
assert_eq "$HOOK_RC" 0 'exits 0'
assert_not_contains "$REPO/src/main/java/My Class.java" UNFORMATTED 'file with a space is formatted'

begin path_with_comma_is_skipped
java_file 'src/main/java/a,b/A.java' UNFORMATTED
(cd "$REPO" && git add .)
run_hook
assert_eq "$HOOK_RC" 0 'exits 0 rather than mis-matching'
assert_contains "$HOOK_OUT" 'comma in the path' 'reports the comma path'
assert_eq "$(wc -l <"$STUB_LOG" | tr -d ' ')" 0 'never invokes maven with an unsplittable value'

begin rename_is_formatted
java_file src/main/java/Old.java UNFORMATTED
(
    cd "$REPO" && git add . && git commit -qm init --no-verify
    git mv src/main/java/Old.java src/main/java/New.java
)
run_hook
assert_eq "$HOOK_RC" 0 'exits 0'
assert_contains "$STUB_LOG" New.java 'a rename is offered to Spotless (ACMR, not ACM)'

begin missing_maven_does_not_block
java_file src/main/java/A.java UNFORMATTED
(cd "$REPO" && git add .)
# A PATH holding everything the hook needs except a build tool. Built out of
# wrapper scripts that exec the real absolute paths.
nomvn="$REPO/.nomvn"
mkdir -p "$nomvn"
for cmd in git awk uname cygpath; do
    real=$(command -v "$cmd" 2>/dev/null) || continue
    [ -n "$real" ] || continue
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$real" >"$nomvn/$cmd"
    chmod +x "$nomvn/$cmd"
done
HOOK_OUT="$REPO/.hook-out"
(cd "$REPO" && PATH="$nomvn" "$TEST_BASH" "$HOOK" >"$HOOK_OUT" 2>&1)
HOOK_RC=$?
assert_eq "$HOOK_RC" 0 'exits 0 when there is no build tool'
assert_contains "$HOOK_OUT" 'skipping Spotless' 'says why it skipped'

begin prefers_mvnw
java_file src/main/java/A.java UNFORMATTED
cp "$BIN/mvn" "$REPO/mvnw"
chmod +x "$REPO/mvnw"
(cd "$REPO" && git add src/main/java/A.java)
rm -f "$BIN/mvn" # only ./mvnw is available
run_hook
assert_eq "$HOOK_RC" 0 'exits 0 using ./mvnw'
assert_contains "$STUB_LOG" spotless:apply 'invoked the wrapper'

begin silent_noop_blocks_commit
STUB_MODE=noop
java_file src/main/java/A.java UNFORMATTED
(cd "$REPO" && git add . && git commit -qm init --no-verify)
(cd "$REPO" && printf 'package p;\nclass C { }\nUNFORMATTED\nz\n' >src/main/java/A.java && git add .)
run_hook
if [ "$HOOK_RC" -ne 0 ]; then ok 'blocks the commit when Spotless matched nothing'; else
    no 'blocks the commit when Spotless matched nothing (exited 0)'
fi
assert_contains "$HOOK_OUT" 'matched none' 'explains the no-op'

begin undercount_warns_but_proceeds
STUB_MODE=partial
java_file src/main/java/A.java UNFORMATTED
java_file src/main/java/B.java UNFORMATTED
(cd "$REPO" && git add .)
run_hook
assert_eq "$HOOK_RC" 0 'exits 0 on a partial match'
assert_contains "$HOOK_OUT" 'matched only' 'warns about the unmatched remainder'

begin maven_failure_blocks_commit
STUB_MODE=fail
java_file src/main/java/A.java UNFORMATTED
(cd "$REPO" && git add .)
run_hook
if [ "$HOOK_RC" -ne 0 ]; then ok 'blocks the commit when maven fails'; else
    no 'blocks the commit when maven fails (exited 0)'
fi
assert_contains "$HOOK_OUT" 'stub maven failure' 'surfaces the maven output'

begin runs_from_a_subdirectory
java_file src/main/java/deep/A.java UNFORMATTED
(cd "$REPO" && git add .)
HOOK_OUT="$REPO/.hook-out"
(
    cd "$REPO/src/main/java/deep" &&
        PATH="$BIN:$PATH" STUB_LOG="$STUB_LOG" STUB_MODE=normal \
            "$TEST_BASH" "$HOOK" >"$HOOK_OUT" 2>&1
)
HOOK_RC=$?
assert_eq "$HOOK_RC" 0 'exits 0'
assert_not_contains "$REPO/src/main/java/deep/A.java" UNFORMATTED 'resolves the repo root from a subdirectory'

# End to end: installed as a real hook and driven by `git commit`, so the shebang
# and git's own hook invocation are exercised rather than bypassed.
begin end_to_end_git_commit
java_file src/main/java/A.java UNFORMATTED
cp "$HOOK" "$REPO/.git/hooks/pre-commit"
chmod +x "$REPO/.git/hooks/pre-commit"
COMMIT_OUT="$REPO/.commit-out"
(
    cd "$REPO" && git add src/main/java/A.java &&
        PATH="$BIN:$(dirname "$(command -v "$TEST_BASH")"):$PATH" \
            STUB_LOG="$STUB_LOG" STUB_MODE=normal \
            git commit -qm formatted >"$COMMIT_OUT" 2>&1
)
COMMIT_RC=$?
assert_eq "$COMMIT_RC" 0 'git commit succeeds'
(cd "$REPO" && git show HEAD:src/main/java/A.java 2>/dev/null) >"$REPO/.head"
assert_not_contains "$REPO/.head" UNFORMATTED 'the commit contains formatted content'

# Simulated Git Bash, for machines that are not Windows. Proves the Windows branch
# converts the path with cygpath, regex-quotes the backslash form, and sets
# MSYS2_ARG_CONV_EXCL so Git Bash does not rewrite the "C:\..." inside the
# argument.
#
# Skipped when already on Windows, where it would be both redundant and wrong:
# redundant because `uname -s` really is MINGW there, so every case above already
# ran through the real cygpath; wrong because the stub cygpath below cannot
# faithfully reverse a real drive-letter path back to a POSIX one.
case $(uname -s) in
MINGW* | MSYS* | CYGWIN*)
    printf '\n== windows_path_translation\n'
    printf '    skipped: on Windows already -- every case above used the real cygpath\n'
    ;;
*)
    begin windows_path_translation
    STUB_MODE=winpath
cat >"$BIN/uname" <<'FAKE_UNAME'
#!/bin/sh
echo MINGW64_NT-10.0-22631
FAKE_UNAME
cat >"$BIN/cygpath" <<'FAKE_CYGPATH'
#!/bin/sh
# emulate: cygpath -w -- /a/b  ->  C:\a\b
last=''
for a in "$@"; do last=$a; done
printf '%s\n' "$last" | sed -e 's|^/|C:/|' -e 's|/|\\|g'
FAKE_CYGPATH
chmod +x "$BIN/uname" "$BIN/cygpath"
java_file 'src/main/java/Program Files (x86)/A.java' UNFORMATTED
(cd "$REPO" && git add .)
run_hook
assert_eq "$HOOK_RC" 0 'exits 0 under a simulated Git Bash'
assert_contains "$STUB_LOG" '\QC:\' 'builds a regex-quoted backslash Windows pattern'
assert_contains "$STUB_LOG" 'MSYS2_ARG_CONV_EXCL=-DspotlessFiles' 'guards against MSYS argument mangling'
    assert_not_contains "$REPO/src/main/java/Program Files (x86)/A.java" UNFORMATTED \
        'formats a Windows-style path containing spaces and metacharacters'
    ;;
esac

# --- opt-in: the real plugin, no stub ----------------------------------------
# E2E=1 drives the whole chain through the real spotless-maven-plugin. That is
# the only way to check the \Q..\E construction against Java's actual regex
# semantics rather than the stub's imitation of them, so run it whenever the
# path handling above changes. Needs Maven, a JDK and (on a cold cache) the
# network, hence opt-in. The plugin version is read from the parent POM so this
# test cannot drift away from what the BOM ships.
if [ "${E2E:-0}" = 1 ]; then
    begin e2e_real_spotless
    SPOTLESS_VERSION=$(sed -n \
        's/.*<spotless-maven-plugin\.version>\([^<]*\)<.*/\1/p' "$HERE/../pom.xml" | head -1)
    printf 'spotless-maven-plugin version under test: %s\n' "${SPOTLESS_VERSION:-UNKNOWN}"
    cat >"$REPO/pom.xml" <<POM
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>e2e</groupId><artifactId>e2e</artifactId><version>1</version>
  <build><plugins><plugin>
    <groupId>com.diffplug.spotless</groupId>
    <artifactId>spotless-maven-plugin</artifactId>
    <version>$SPOTLESS_VERSION</version>
    <configuration><java>
      <includes><include>src/main/java/**/*.java</include></includes>
      <removeUnusedImports/>
    </java></configuration>
  </plugin></plugins></build>
</project>
POM
    # A directory whose name is full of regex metacharacters: unquoted, this is
    # the silent no-op that shipped in the first version of this hook.
    mkdir -p "$REPO/src/main/java/weird (x86)+dir"
    printf 'package p;\nimport java.util.List;\nclass C { }\n' \
        >"$REPO/src/main/java/weird (x86)+dir/C.java"
    (cd "$REPO" && git add .)
    HOOK_OUT="$REPO/.hook-out"
    (cd "$REPO" && "$TEST_BASH" "$HOOK" >"$HOOK_OUT" 2>&1)
    HOOK_RC=$?
    assert_eq "$HOOK_RC" 0 'exits 0 with the real plugin'
    staged_content 'src/main/java/weird (x86)+dir/C.java' >"$REPO/.idx"
    assert_not_contains "$REPO/.idx" 'import java.util.List' \
        'real Spotless formatted a metacharacter path and the result was staged'
fi

# --- summary -----------------------------------------------------------------

printf '\n--------------------------------------------------\n'
printf 'bash under test: %s\n' "$("$TEST_BASH" -c 'echo $BASH_VERSION')"
printf 'git:             %s\n' "$(git --version)"
printf 'passed: %s   failed: %s\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
    printf 'failures:%s\n' "$FAILED_CASES"
    exit 1
fi
printf 'ALL GREEN\n'
