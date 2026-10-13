# Feature: Note History

The system SHALL list notes in most-recently-changed order.

## Background

* Every note carries a last-changed timestamp.
* The list view shows every note in the collection.

## Scenarios

### Scenario: Newest note first

* *GIVEN* a collection with notes "A" and "B"
* *WHEN* note "A" is changed after note "B"
* *THEN* the list SHALL show note "A" before note "B"

### Scenario: Deleted notes leave the list

* *GIVEN* a collection with one note
* *WHEN* the user deletes that note
* *THEN* the list SHALL be empty
