# Feature: Create Note

The system SHALL let a user create a note from a title and a body.

## Background

* A note has a title, a body, and a last-changed timestamp.
* The app holds notes in browser memory.

## Scenarios

### Scenario: Create a note from a title and body

* *GIVEN* an empty note collection
* *WHEN* the user creates a note titled "Groceries" with a body
* *THEN* the collection SHALL contain one note
* *AND* that note SHALL carry the title "Groceries"
* *AND* that note SHALL carry a last-changed timestamp

### Scenario: Reject a note without a title

* *GIVEN* an empty note collection
* *WHEN* the user creates a note with an empty title
* *THEN* the system SHALL reject the request
* *AND* the collection SHALL remain empty
