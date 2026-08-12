package com.otilm.selftest;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * Fixture for the array-initializer settings as they show up in an annotation's brace-delimited member value. Eclipse
 * formats an annotation member array with the same rules as a plain array initializer, so this fixture and the String[]
 * field in {@link Wrapping} guard the same three settings from opposite ends.
 *
 * <p>
 * The methods are empty and unreachable by design; only the source shape is the assertion. Do not "tidy" the layout —
 * it is what spotless:apply produces, and any hand edit will be reported as a violation on the next check.
 */
public final class Annotations {

    private Annotations() {
        throw new AssertionError("no instances");
    }

    /**
     * Several elements, together well over the margin.
     */
    @Responses({
            @Response(status = 200, description = "Supported key usages retrieved"),
            @Response(status = 422, description = "Request validation failed",
                    content = @Content(mediaType = "application/problem+json", schema = "ProblemDetailExtended"))})
    public static void multipleElementsOverMargin() {
    }

    /**
     * Several elements that fit comfortably.
     */
    @Responses({@Response(status = 200), @Response(status = 404)})
    public static void multipleElementsUnderMargin() {
    }

    /** One short element, left inline — the shape a forced alignment or an unconditional brace setting would break. */
    @Responses({@Response(status = 204, description = "no content")})
    public static void singleElement() {
    }

    /** Empty member array, which keep_empty_array_initializer_on_one_line holds together. */
    @Responses({})
    public static void noElements() {
    }

    /**
     * These literals carry no annotation and are nowhere near the margin, so they must survive untouched.
     */
    public static byte[] shortLiteralsStayIntact() {
        int[] triple = {1, 2, 3};
        return new byte[]{(byte) triple[0], (byte) triple[1], (byte) triple[2]};
    }

    /**
     * Two arguments whose combined length passes the margin.
     */
    @Doc(name = "Discovery Operations",
            description = "Stateless run lifecycle: initiate a run, poll or stream its results, and control "
                    + "it. Every call carries the full context; the connector holds no state between calls.")
    public static void annotationArgumentsOverMargin() {
    }

    @Retention(RetentionPolicy.SOURCE)
    @Target(ElementType.METHOD)
    private @interface Doc {
        String name();

        String description();
    }

    @Retention(RetentionPolicy.SOURCE)
    @Target(ElementType.METHOD)
    private @interface Responses {
        Response[] value();
    }

    @Retention(RetentionPolicy.SOURCE)
    @Target({})
    private @interface Response {
        int status();

        String description() default "";

        Content content() default @Content;
    }

    @Retention(RetentionPolicy.SOURCE)
    @Target({})
    private @interface Content {
        String mediaType() default "";

        String schema() default "";
    }
}
