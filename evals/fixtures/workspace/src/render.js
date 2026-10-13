// Renders store state into DOM. Reads state, never mutates it.

const THEMES = ["light", "dark"];

export function render(root, notes, theme = "light") {
  if (!THEMES.includes(theme)) throw new Error(`unknown theme ${theme}`);
  root.dataset.theme = theme;
  root.replaceChildren(...notes.map(noteElement));
}

function noteElement(note) {
  const element = document.createElement("article");
  element.className = "note";
  element.dataset.id = note.id;

  const title = document.createElement("h2");
  title.textContent = note.title;

  const body = document.createElement("p");
  body.textContent = note.body;

  element.append(title, body);
  return element;
}
