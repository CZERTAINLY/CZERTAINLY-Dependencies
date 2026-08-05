package com.otilm.selftest;

import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.concurrent.TimeUnit;

import static java.util.Comparator.comparing;
import static java.util.Objects.requireNonNull;
import static java.util.stream.Collectors.toList;

/**
 * Fixture for otilm/eclipse.importorder: one alphabetical block, a blank line, then statics last.
 *
 * <p>
 * Every import below is used. That is load-bearing: Spotless runs removeUnusedImports, so an unused one would be
 * deleted and this file would fail its own check for the wrong reason. Adding an import here means using it.
 */
public final class Imports {

    private Imports() {
    }

    static Map<String, Long> timings(List<String> labels, Set<String> excluded) {
        requireNonNull(labels, "labels");
        Map<String, Long> result = new TreeMap<>();
        List<String> kept = labels
                .stream()
                .filter(label -> !excluded.contains(label))
                .sorted(comparing(String::length))
                .collect(toList());
        for (String label : kept) {
            result.put(label, TimeUnit.SECONDS.toMillis(label.length()));
        }
        return result;
    }
}
