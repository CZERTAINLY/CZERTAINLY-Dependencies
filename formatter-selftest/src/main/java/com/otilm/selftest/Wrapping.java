package com.otilm.selftest;

import java.io.IOException;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Fixture for the wrapping and continuation-indent settings, which are where the Eclipse profile and IntelliJ's engine
 * diverge most and therefore where drift shows up first.
 *
 * <p>
 * Every construct here is over the 120-column margin on purpose, so the formatter has to decide where to break and how
 * far to indent the continuation. Do not "tidy" these lines: their exact shape is the assertion.
 */
public final class Wrapping {

    private static final Map<String, List<String>> PRESETS = Map
            .of("alpha", List.of("one", "two", "three"), "beta", List.of("four", "five", "six"), "gamma",
                    List.of("seven", "eight", "nine"));

    private final String[] names = {
            "first",
            "second",
            "third",
            "fourth",
            "fifth",
            "sixth",
            "seventh",
            "eighth",
            "ninth",
            "tenth",
            "eleventh",
            "twelfth"};

    /**
     * A fluent chain in the narrow window that only alignment_for_assignment can break: it overflows the margin by less
     * than the 8 columns that wrapping after the '=' would buy. Setting alignment_for_assignment therefore frees just
     * enough width for the whole chain to fit. Do not shorten the {@code result} local or its chain.
     */
    public static List<String> chainInTheAssignmentWindow(List<String> values) {
        List<String> result = values
                .stream()
                .map(String::strip)
                .filter(value -> !value.isEmpty())
                .sorted()
                .distinct()
                .toList();
        return result;
    }

    private Wrapping() {
        throw new AssertionError("no instances");
    }

    /**
     * Exercises a long parameter list, a long throws list, and a wrapped binary expression.
     *
     * @param source where to read from
     * @param destination where to write to
     * @param encoding the charset name
     * @param overwrite whether an existing destination may be replaced
     * @return the number of bytes transferred
     * @throws IOException if either side fails
     * @throws IllegalStateException if the destination exists and overwrite is false
     */
    public static long transfer(Path source, Path destination, String encoding, boolean overwrite)
            throws IOException, IllegalStateException {
        if (source == null || destination == null || encoding == null || encoding.isBlank()
                || !overwrite && destination.toFile().exists()) {
            throw new IllegalStateException("refusing to transfer with an incomplete or conflicting configuration");
        }
        return source.toFile().length() + destination.toFile().length() + encoding.length();
    }

    /** Exercises a wrapped method-call chain and a wrapped ternary. */
    public static String describe(List<String> values, boolean verbose) {
        String joined = values
                .stream()
                .filter(value -> value != null && !value.isBlank())
                .map(String::trim)
                .distinct()
                .sorted()
                .reduce("", (left, right) -> left.isEmpty() ? right : left + ", " + right);
        return verbose ? "values=[" + joined + "] count=" + values.size() + " presets=" + PRESETS.size() : joined;
    }

    /** Exercises a nested lambda and Optional chaining, both continuation-indent sensitive. */
    public Optional<String> firstMatching(String prefix) {
        return List.of(names).stream().filter(name -> name.startsWith(prefix)).findFirst().map(name -> {
            String upper = name.toUpperCase();
            return upper.substring(0, 1) + name.substring(1);
        });
    }
}
