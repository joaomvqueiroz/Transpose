/* Transpono Gecko bridge (built-in extension background script).
 *
 * Sets the cookies of the user's own Google sign-in, copied by the app from
 * Safari's engine (where Google lets them sign in) so that YouTube opens
 * signed in here too. Only Google and YouTube domains, only on request from
 * this extension's own relay content script.
 */
'use strict';

const GOOGLE = /(^|\.)(youtube\.com|google\.(com|[a-z]{2}|com?\.[a-z]{2}))$/;

browser.runtime.onMessage.addListener(async (message, sender) => {
  if (!message || message.type !== 'setCookies' || sender.id !== browser.runtime.id) return;
  let ok = 0;
  let failed = 0;
  for (const cookie of Array.isArray(message.cookies) ? message.cookies : []) {
    const domain = String(cookie.domain || '');
    const host = domain.replace(/^\./, '');
    if (!GOOGLE.test(host)) { failed++; continue; }
    const path = cookie.path || '/';
    const details = {
      url: `https://${host}${path}`,
      name: String(cookie.name),
      value: String(cookie.value),
      path,
      secure: !!cookie.secure,
      httpOnly: !!cookie.httpOnly,
    };
    // A leading dot means a domain cookie; without it the cookie is host-only.
    if (domain.startsWith('.')) details.domain = host;
    if (typeof cookie.expirationDate === 'number') details.expirationDate = cookie.expirationDate;
    if (cookie.sameSite) details.sameSite = cookie.sameSite;
    try {
      await browser.cookies.set(details);
      ok++;
    } catch (_) {
      failed++;
    }
  }
  return {ok, failed};
});
