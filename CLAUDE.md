# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Maven parent POM** (no application source code) that serves as the centralized dependency management BOM for the ILM platform. Java/Spring Boot modules and connectors inherit from this POM to get standardized, pre-vetted library versions.

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

There are no tests or source code to compile in this repository itself. The `verify` phase validates the POM structure and runs JaCoCo (inherited by child projects).

## Versioning Rules

- **main branch**: Version MUST be a `-SNAPSHOT` (e.g., `1.4.1-SNAPSHOT`)
- **Tagged releases**: Version MUST NOT contain `SNAPSHOT` (e.g., `1.4.0`)
- CI enforces this: publishing will fail if the version/ref-type combination is wrong

## Maven Profiles

- **`central`**: Publishes to Maven Central Portal with GPG signing. Requires `MAVEN_GPG_PRIVATE_KEY`, `MAVEN_GPG_PASSPHRASE`, and Central Portal credentials. After deployment, releases sit in VALIDATED state until manually published in the Portal UI.
- **`github`**: Publishes to GitHub Packages.

## Key Plugin Configuration (inherited by child projects)

- **Surefire** opens `java.base` modules (`java.lang`, `sun.security.rsa`, `sun.security.x509`) via `--add-opens` for security-related tests
- **Hibernate enhance** plugin enables lazy initialization bytecode enhancement
- **JaCoCo** runs coverage during the `package` phase
- **maven-jar-plugin** disables Maven descriptor in archives (`addMavenDescriptor: false`)
- **maven-compiler-plugin** enables `parameters=true` for reflection support

## Dependency Updates

Automated via Renovate (`renovate.json`). PRs are created automatically when new dependency versions are available.
