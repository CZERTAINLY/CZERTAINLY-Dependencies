#!/usr/bin/env bash
# Pre-commit hook: run Spotless on the staged Java files and re-stage the result.
#
# Auto-installed into .git/hooks/ on the first Maven build of a clone by the
# git-build-hook-maven-plugin -- there is no manual install step.
#
# To bypass for an emergency commit: git commit --no-verify
# CI (mvn verify) remains the authoritative gate either way.
#
# -----------------------------------------------------------------------------
# Portability contract. Every item here has broken this hook before; re-run
# scripts/test-pre-commit.sh after editing.
#
#   bash 3.2   macOS ships 3.2.57 as /bin/bash and GUI git clients hand hooks a
#              reduced PATH, so `mapfile` (bash 4.0) is unavailable -- and under
#              `set -u`, "${arr[@]}" on an EMPTY array is an "unbound variable"
#              error before bash 4.4, hence the ${arr[@]+"${arr[@]}"} guards.
#   Git Bash   git reports forward-slash paths, the JVM reports backslash ones.
#   paths      -DspotlessFiles is a REGEX, not a path list. See below.
# -----------------------------------------------------------------------------
set -euo pipefail

warn() { printf 'pre-commit: %s\n' "$*" >&2; }
die() {
    warn "$*"
    exit 1
}

repo_root=$(git rev-parse --show-toplevel) ||
    die 'cannot locate the work tree root (not a git repository, or git not on PATH)'
cd "$repo_root"

# A missing build tool must not make committing impossible: warn and let the
# commit through, because `mvn verify` in CI still gates the branch.
if [[ -x ./mvnw ]]; then
    maven=./mvnw
elif command -v mvn >/dev/null 2>&1; then
    maven=mvn
else
    warn 'neither ./mvnw nor mvn on PATH; skipping Spotless (CI still gates this)'
    exit 0
fi

# Collect the staged Java files. bash 3.2 has no `mapfile`, so read the
# NUL-delimited list with a loop. ACMR rather than ACM: a rename (R) carries
# content that still needs formatting.
staged=()
while IFS= read -r -d '' file; do
    staged+=("$file")
done < <(git diff --cached --name-only --diff-filter=ACMR -z -- '*.java')

[[ "${#staged[@]}" -ne 0 ]] || exit 0

# `git add` stages a file's CURRENT WORKTREE content, not the formatted version of what was staged.
formattable=()
partial=()
for file in ${staged[@]+"${staged[@]}"}; do
    if git diff --quiet -- "$file"; then
        formattable+=("$file")
    else
        partial+=("$file")
    fi
done

if [[ "${#partial[@]}" -ne 0 ]]; then
    warn 'left alone -- these have unstaged changes that re-staging would sweep into the commit:'
    for file in ${partial[@]+"${partial[@]}"}; do warn "    $file"; done
    warn 'stage them completely, or run "mvn spotless:apply" yourself, before pushing.'
fi

[[ "${#formattable[@]}" -ne 0 ]] || exit 0

# -DspotlessFiles is NOT a list of paths: spotless-maven-plugin splits the value
# on ',', Pattern.compile()s each piece, and full-matches it against
# File.getAbsolutePath(). Four consequences:
#
#   * the path must be spelled the way the JVM will spell it -- backslashes on
#     Windows, where git hands us forward slashes; hence cygpath.
#   * every path must be regex-quoted with \Q..\E. Without it a directory named
#     "Program Files (x86)" matches NOTHING, Spotless formats nothing, and the
#     build still exits 0 -- a silent no-op that lands unformatted code.
#   * \Q..\E is not itself nestable: a literal \E INSIDE the path closes the
#     quoted span early and the remainder is read as raw regex. Consider
#     "C:\Eclipse\..." on Windows.
#   * a ',' in a path cannot survive the plugin's split(), so such a file is
#     reported and skipped rather than silently mis-matched.
case $(uname -s) in
MINGW* | MSYS* | CYGWIN*) windows=1 ;;
*) windows=0 ;;
esac

patterns=''
targets=()
uncommaable=()
for file in ${formattable[@]+"${formattable[@]}"}; do
    abs="$repo_root/$file"
    if [[ "$windows" -eq 1 ]] && command -v cygpath >/dev/null 2>&1; then
        abs=$(cygpath -w -- "$abs")
    fi
    case $abs in
    *,*)
        uncommaable+=("$file")
        continue
        ;;
    *) ;; # every other path is usable as-is; fall through to the quoting below
    esac
    esc=${abs//'\E'/'\E\\E\Q'}
    patterns="${patterns:+$patterns,}\\Q$esc\\E"
    targets+=("$file")
done

if [[ "${#uncommaable[@]}" -ne 0 ]]; then
    warn 'left alone -- a comma in the path cannot be passed through -DspotlessFiles:'
    for file in ${uncommaable[@]+"${uncommaable[@]}"}; do warn "    $file"; done
fi

[[ -n "$patterns" ]] || exit 0

# Deliberately not -q: the "Spotless.Java is keeping N files clean" line is the
# only evidence that the regex above actually matched, and -q suppresses it.
# MSYS2_ARG_CONV_EXCL stops Git Bash from rewriting the "C:\..." inside the
# argument as though it were a POSIX path list.
if ! output=$(MSYS2_ARG_CONV_EXCL='-DspotlessFiles' \
    "$maven" -B spotless:apply -DspotlessFiles="$patterns" 2>&1); then
    printf '%s\n' "$output" >&2
    die 'mvn spotless:apply failed; nothing was re-staged'
fi

# Confirm Spotless actually saw the files we asked for. The count is printed once
# per module, so sum it across the reactor. A total of zero means the
# path-to-regex translation above is wrong for this platform -- the failure mode
# that otherwise passes silently and commits unformatted code.
matched=$(printf '%s\n' "$output" | awk '
    match($0, /Spotless\.Java is keeping [0-9]+ files clean/) {
        n = substr($0, RSTART, RLENGTH)
        gsub(/[^0-9]/, "", n)
        total += n
    }
    END { print total + 0 }
')

if [[ "$matched" -eq 0 ]]; then
    printf '%s\n' "$output" >&2
    die "Spotless matched none of the ${#targets[@]} staged file(s). Either this hook's
            path handling is wrong on this platform (please report it), or the files sit
            outside the configured Spotless <includes>. Commit blocked rather than
            silently committing unformatted code; use --no-verify to override."
elif [[ "$matched" -lt "${#targets[@]}" ]]; then
    warn "Spotless matched only $matched of the ${#targets[@]} staged file(s); the rest are
            probably outside its configured <includes> and remain unformatted."
fi

git add -- ${targets[@]+"${targets[@]}"}
