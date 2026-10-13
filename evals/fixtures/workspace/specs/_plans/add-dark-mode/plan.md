# Plan: add-dark-mode

## Summary

Add a dark theme to the app shell and let the user switch between light and
dark.

## Context

- The app shell currently renders with a single hard-coded light palette.
- `specs/architecture.md` records that theme selection belongs to the app shell.
- See `architecture.md` in this directory for the delta.

## Features

| Feature | Status | Spec |
|---------|--------|------|
| theme | NEW | `notes/theme/spec.md` |

## Impact

Users can switch the app to a dark palette. No breaking changes.

## Requirements

| Requirement | Details |
|-------------|---------|
| Persistence | The chosen theme survives a reload |
