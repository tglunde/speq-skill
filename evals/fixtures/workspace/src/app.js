// App shell. Wires the store to the renderer and owns the theme.

import { createStore } from "./store.js";
import { render } from "./render.js";

const THEME_KEY = "acme-notes-theme";

export function boot(root) {
  const store = createStore();
  let theme = localStorage.getItem(THEME_KEY) ?? "light";

  const draw = () => render(root, store.list(), theme);

  store.subscribe(draw);
  draw();

  return {
    setTheme(next) {
      theme = next;
      localStorage.setItem(THEME_KEY, next);
      draw();
    },
    create: store.create,
    update: store.update,
    remove: store.remove,
  };
}
