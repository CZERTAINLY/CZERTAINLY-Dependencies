# CZERTAINLY Dependencies

> This repository is part of the commercial open source project CZERTAINLY. You can find more information about the project at [CZERTAINLY](https://github.com/CZERTAINLY/CZERTAINLY) repository, including the contribution guide.

`Dependencies` provides the basic setting of libraries for the CZERTAINLY platform in case modules or connectors are written in `Java`. There are pre-defined libraries which CZERTAINLY would like to use over the modules and connectors. 

The settings are based on Spring Boot and their compliant dependencies that are regularly updated.

For more information, see [pom.xml](./pom.xml).

## Maven

`Dependencies` are available in the Maven Central Repository. To use them, add the following to your `pom.xml`:

```xml
<parent>
    <groupId>com.czertainly</groupId>
    <artifactId>dependencies</artifactId>
    <version>${version}</version>
</parent>
```
