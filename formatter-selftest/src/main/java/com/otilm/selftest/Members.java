package com.otilm.selftest;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

/**
 * Fixture for blank-line handling, brace placement and the member layout settings.
 *
 * <p>
 * Eclipse collapses runs of blank lines to one (number_of_empty_lines_to_preserve=1) and IntelliJ splits that single
 * knob into three .editorconfig properties. The single blank lines below are what both engines must converge on, so
 * this file fails if either side's setting is dropped.
 */
public class Members {

    /** Nested enum: exercises constant layout and the blank line after a class header. */
    public enum State {

        PENDING,
        ACTIVE,
        CLOSED;

        boolean terminal() {
            return this == CLOSED;
        }
    }

    /** Record header wrapping is one of the known IntelliJ/Eclipse divergences. */
    public record Window(String label, Duration length, State state, int priority, boolean sticky) {

        public Window {
            if (length.isNegative()) {
                throw new IllegalArgumentException("length must not be negative");
            }
        }
    }

    private static final int MAX = 16;

    private final List<Window> windows = new ArrayList<>();
    private State state = State.PENDING;

    public Members() {
        this.state = State.PENDING;
    }

    /**
     * Single-statement bodies must still carry braces — Checkstyle NeedBraces enforces what the formatter cannot.
     */
    public void add(Window window) {
        if (windows.size() >= MAX) {
            throw new IllegalStateException("too many windows");
        }
        if (window.state().terminal()) {
            return;
        }
        windows.add(window);
    }

    public State state() {
        return state;
    }

    void close() {
        for (Window window : windows) {
            if (window.sticky()) {
                continue;
            }
            state = State.CLOSED;
        }
        while (!windows.isEmpty()) {
            windows.remove(windows.size() - 1);
        }
    }

    /** An anonymous class body, which has its own brace and indentation rules. */
    Runnable asTask() {
        return new Runnable() {

            @Override
            public void run() {
                close();
            }
        };
    }
}
