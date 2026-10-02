# ADR 0005: iOS and iPadOS 26 minimum

- Status: accepted
- Date: 2026-10-02

## Context

The app depends on Observation, SwiftData and Swift concurrency, and its AI features on Foundation Models, which ships with iOS 26. Development starts in October 2026, when iOS 27 is the current release.

## Decision

The deployment target is iOS and iPadOS 26.0: the current release and the one before it. APIs newer than iOS 26 are used behind availability checks.

## Consequences

- Foundation Models and the current SwiftData are available without availability branches.
- Devices that cannot run iOS 26 are not supported.
- AI availability still varies by device and settings (Apple Intelligence), so capability detection is required regardless of OS version.
