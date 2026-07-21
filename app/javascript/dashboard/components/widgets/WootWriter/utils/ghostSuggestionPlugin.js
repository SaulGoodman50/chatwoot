import { Plugin, PluginKey } from 'prosemirror-state';
import { Decoration, DecorationSet } from 'prosemirror-view';

// SDS patch: renders the pending AI reply suggestion as grey inline "ghost
// text" at the cursor, Copilot-style. The suggestion itself lives outside the
// editor (ReplyBox owns fetching and visibility); this plugin only draws
// whatever the getter returns, so an empty string hides it.
export const ghostSuggestionPluginKey = new PluginKey('ghostSuggestion');

export function createGhostSuggestionPlugin(getSuggestion, hintLabel = 'tab') {
  return new Plugin({
    key: ghostSuggestionPluginKey,
    props: {
      decorations(state) {
        const text = getSuggestion();
        if (!text) return DecorationSet.empty;
        const widget = Decoration.widget(
          state.selection.head,
          () => {
            const wrapper = document.createElement('span');
            wrapper.className = 'ghost-suggestion';
            wrapper.textContent = text;
            const hint = document.createElement('span');
            hint.className = 'ghost-suggestion--hint';
            hint.textContent = hintLabel;
            wrapper.appendChild(hint);
            return wrapper;
          },
          { side: 1, ignoreSelection: true, key: `ghost-${text}` }
        );
        return DecorationSet.create(state.doc, [widget]);
      },
    },
  });
}
