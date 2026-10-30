import { GlobalStyles } from '../styles';

const VOKOP_GLOBAL_STYLES_ID = 'vokop-global-styles';

export function injectGlobalStyles() {
  if (document.getElementById(VOKOP_GLOBAL_STYLES_ID)) {
    return;
  }

  document.head.insertAdjacentHTML(
    'beforeend',
    `
        <style id="${VOKOP_GLOBAL_STYLES_ID}">
          ${GlobalStyles}
        </style>
    `,
  );
}
