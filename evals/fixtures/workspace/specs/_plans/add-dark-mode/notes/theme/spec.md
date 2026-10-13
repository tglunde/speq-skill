# Feature: Theme

The system SHALL render the interface in a light or dark theme.

## Background

* Theme selection belongs to the app shell.
* The chosen theme persists across reloads.

## Scenarios

### Scenario: Default theme on a first visit

* *GIVEN* a visitor with no stored preference
* *WHEN* the app loads
* *THEN* the app SHALL render in the light theme

### Scenario: Dark theme persists

* *GIVEN* a visitor with no stored preference
* *WHEN* the visitor selects the dark theme
* *AND* the visitor reloads the app
* *THEN* the app SHALL render in the dark theme
