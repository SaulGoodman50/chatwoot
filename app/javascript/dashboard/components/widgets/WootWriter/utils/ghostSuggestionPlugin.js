import { Plugin, PluginKey } from 'prosemirror-state';
import { Decoration, DecorationSet } from 'prosemirror-view';

// SDS patch: renders the pending AI reply suggestion as grey inline "ghost
// text" at the cursor, Copilot-style. The suggestion itself lives outside the
// editor (ReplyBox owns fetching and visibility); this plugin only draws
// whatever the getters return, so an empty string hides it. While a suggestion
// is still being generated it draws a pulsing loading hint instead.
export const ghostSuggestionPluginKey = new PluginKey('ghostSuggestion');

export function createGhostSuggestionPlugin(
  getSuggestion,
  getLoading = () => false,
  hintLabel = 'tab',
  loadingLabel = 'AI-suggestie'
) {
  return new Plugin({
    key: ghostSuggestionPluginKey,
    props: {
      decorations(state) {
        const text = getSuggestion();
        const loading = !text && getLoading();
        if (!text && !loading) return DecorationSet.empty;
        const widget = Decoration.widget(
          state.selection.head,
          () => {
            const wrapper = document.createElement('span');
            wrapper.className = 'ghost-suggestion';
            if (loading) {
              wrapper.classList.add('ghost-suggestion--loading');
              wrapper.textContent = loadingLabel;
              const dots = document.createElement('span');
              dots.className = 'ghost-suggestion--dots';
              wrapper.appendChild(dots);
            } else {
              wrapper.textContent = text;
              const hint = document.createElement('span');
              hint.className = 'ghost-suggestion--hint';
              hint.textContent = hintLabel;
              wrapper.appendChild(hint);
            }
            return wrapper;
          },
          {
            side: 1,
            ignoreSelection: true,
            key: loading ? 'ghost-loading' : `ghost-${text}`,
          }
        );
        return DecorationSet.create(state.doc, [widget]);
      },
    },
  });
}
