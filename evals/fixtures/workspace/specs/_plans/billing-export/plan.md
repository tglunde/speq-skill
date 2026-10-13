# Plan: billing-export

## Summary

Export a user's notes as a monthly billing statement.

## Context

- Billing needs a machine-readable export of note activity per month.
- No export path exists today.

## Features

| Feature | Status | Spec |
|---------|--------|------|
| billing-export | NEW | `billing/export/spec.md` |

## Impact

Adds a new export endpoint. No breaking changes.

## Requirements

| Requirement | Details |
|-------------|---------|
| Format | One CSV row per note change |
