// WHIP's active skin. whip_core injects <link href="https://cfx-nui-<theme>/theme.css"> into its
// own page; this page is a separate document, so it does the same with the theme name the server
// sends on open (GetActiveTheme). Appended last, so the theme's tokens win, exactly as in WHIP.
// Fails soft: a theme that cannot load is removed and WHIP's base look stays.
const LINK_ID = 'whip-theme'
const RESOURCE_NAME = /^[A-Za-z0-9_-]{1,64}$/   // a resource name only, never a URL

export const applyWhipTheme = (resource) => {
  const existing = document.getElementById(LINK_ID)
  if (existing) {
    if (existing.dataset.resource === resource) return
    existing.remove()
  }
  if (!resource) return
  if (typeof resource !== 'string' || !RESOURCE_NAME.test(resource)) return
  const link = document.createElement('link')
  link.id = LINK_ID
  link.rel = 'stylesheet'
  link.dataset.resource = resource
  link.href = 'https://cfx-nui-' + resource + '/theme.css'
  link.onerror = () => {
    console.error('[whip_cine] theme.css could not be loaded from "' + resource + '"; using WHIP\'s base look.')
    link.remove()
  }
  document.head.appendChild(link)
}
