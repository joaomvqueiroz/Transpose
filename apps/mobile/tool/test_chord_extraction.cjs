const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const dart = fs.readFileSync(path.join(__dirname, '../lib/chord_browser.dart'), 'utf8');
const script = dart.match(/const chordExtractionScript = r'''([\s\S]*?)''';/)[1];
function element(text, hidden = false) {
  return { innerText: text, nodeType: 1, hidden, parentElement: null,
    getAttribute: () => null, getClientRects: () => [{}] };
}
function extract(elements) {
  return JSON.parse(vm.runInNewContext(script, {
    location: {href: 'https://www.cifras.com.br/cifra/estudo/original'},
    document: {title: 'Estudo', querySelector: () => null, querySelectorAll: () => elements},
    getComputedStyle: () => ({display: 'block', visibility: 'visible'}),
  }));
}
assert.equal(extract([element('C   G/B\nLetra original\nAm  F')]).text, 'C   G/B\nLetra original\nAm  F');
assert.equal(extract([element('C G', true)]).error, 'no-visible-chord');
assert.equal(extract([element('Aguarde a verificação')]).error, 'no-visible-chord');
assert.equal(extract([element('C '.repeat(6000))]).error, 'too-long');
assert.equal(extract([element('navegação'), element('Am   F\nOriginal')]).text, 'Am   F\nOriginal');
const hiddenParent = element('parent', true);
const child = element('C G'); child.parentElement = hiddenParent;
assert.equal(extract([child]).error, 'no-visible-chord');
console.log('6 DOM extraction checks passed (synthetic original text only).');
