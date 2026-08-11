package com.otilm.selftest;

/**
 * Fixture for {@code alignment_for_enum_constants}, which governs whether a constant list is packed onto shared lines
 * or broken one constant per line.
 *
 * <p>
 * The two enums below are deliberately different shapes, because they catch different mutations. {@link Signal} is
 * short enough that its whole constant list fits inside the 120-column margin, so it fails the moment the force bit is
 * dropped (value 48 instead of 49) or the setting is removed altogether. {@link Category} overflows the margin, so it
 * fails when the setting is removed and the JDT default packs the constants into a staircase.
 *
 * <p>
 * Do not "tidy" either list onto fewer lines: their exact shape is the assertion.
 */
public final class Enums {

    private Enums() {
        throw new AssertionError("no instances");
    }

    /** Short enough to fit on one line, so it pins the force bit rather than the wrap style. */
    public enum Signal {
        LOW,
        MEDIUM,
        HIGH
    }

    /** Wide enough to overflow the margin, so it pins the one-per-line wrap style. */
    public enum Category {
        RDN_ATTRIBUTE_TYPE("2.5.4.3", "Relative distinguished name attribute type"),
        EXTENDED_KEY_USAGE("2.5.29.37", "Extended key usage extension identifier"),
        CERTIFICATE_POLICY("2.5.29.32", "Certificate policy extension identifier"),
        SUBJECT_ALTERNATIVE_NAME("2.5.29.17", "Subject alternative name extension identifier");

        private final String oid;

        private final String label;

        Category(String oid, String label) {
            this.oid = oid;
            this.label = label;
        }

        public String oid() {
            return oid;
        }

        public String label() {
            return label;
        }
    }
}
