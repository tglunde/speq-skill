// Note store. Holds the collection and notifies subscribers.
// Knows nothing about the DOM.

export function createStore(initial = []) {
  let notes = [...initial];
  const subscribers = new Set();

  function notify() {
    for (const subscriber of subscribers) subscriber(notes);
  }

  return {
    subscribe(subscriber) {
      subscribers.add(subscriber);
      return () => subscribers.delete(subscriber);
    },
    list() {
      return [...notes].sort((a, b) => b.changedAt - a.changedAt);
    },
    create({ title, body = "" }) {
      if (!title) throw new Error("title is required");
      const note = { id: crypto.randomUUID(), title, body, changedAt: Date.now() };
      notes.push(note);
      notify();
      return note;
    },
    update(id, patch) {
      const note = notes.find((candidate) => candidate.id === id);
      if (!note) throw new Error(`unknown note ${id}`);
      Object.assign(note, patch, { changedAt: Date.now() });
      notify();
      return note;
    },
    remove(id) {
      notes = notes.filter((candidate) => candidate.id !== id);
      notify();
    },
  };
}
