# Architecture: Acme Notes

## Overview

A single-page web app. The browser holds the note state and renders the
interface. There is no server component.

## Components

| Component | Responsibility |
|-----------|----------------|
| `src/app.js` | Boots the app, wires the store to the renderer |
| `src/store.js` | Holds the note collection and notifies subscribers |
| `src/render.js` | Turns store state into DOM |

## Boundaries

- The store knows nothing about the DOM.
- The renderer reads store state and never mutates it.
- Theme selection is a property of the app shell, not of an individual note.

## Data Flow

1. A user action calls a store mutation.
2. The store notifies its subscribers.
3. The renderer redraws from the new state.
