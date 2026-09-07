// Run with Node and jsdom available (test-only dependency).
const { JSDOM } = require('jsdom');
const { readFileSync } = require('node:fs');
const assert = require('node:assert/strict');
const template = readFileSync(require('node:path').join(__dirname, '../templates/atc-map.html'), 'utf8');
const dom = new JSDOM('<button id="np-favorite">Favorite</button><div id="popup"></div>', { runScripts: 'outside-only' });
const w = dom.window;
function load(name) {
    const start = template.indexOf('        function ' + name + '(');
    const end = template.indexOf('\n        function ', start + 1);
    w.eval(template.slice(start, end));
}
['syncCurrentFavoriteControl', 'getMarkerVisual', 'buildMarkerPopupHtml', 'formatWeatherAge', 'escapeHtml', 'applyWeatherMarkerUpdates'].forEach(load);
const popup = w.document.getElementById('popup');
const m = { icao: 'EHAM', name: 'Test', favCount: 0, isFav: false, fcat: 'VFR',
    airportFavHtml: '<div class="airport-favorite-row"><button class="airport-favorite-link">☆ Add airport favorite</button></div>',
    desc: ['Tower', 'Approach'].map(channel => '<button class="favorite-link" data-channel="' + channel + '">☆ Add favorite</button>').join('') };
const item = { data: m, layer: {
    getPopup: () => ({ getElement: () => popup }),
    setPopupContent: html => { popup.innerHTML = html; },
    bindPopup: html => { popup.innerHTML = html; },
    setStyle: () => {}, setRadius: () => {}
} };
w.allMapItems = [item]; w.mapItemsByIcao = { EHAM: item }; w.currentPlayingItem = null;
w.setAirportMarkerStyle = () => {};
w.buildWindMarker = () => null;
let filters = 0;
w.applyFilters = () => { filters++; };
const favorite = channel => ({ ICAO: 'EHAM', Channel: channel, Count: 1 });
const sync = channels => w.syncCurrentFavoriteControl({ ok: true, favorites: channels.map(favorite) });
for (let i = 0; i < 3; i++) {
    sync(['Tower', 'Approach', '__AIRPORT__']);
    assert.equal(m.isFav, true); assert.equal(m.favCount, 3); assert.equal(item.cat, 'fav');
    popup.querySelector('[data-channel="Tower"]').focus();
    sync(['Approach', '__AIRPORT__']);
    assert.equal(w.document.activeElement.getAttribute('data-channel'), 'Tower');
    assert.equal(w.document.activeElement.getAttribute('aria-pressed'), 'false');
    assert.equal(m.isFav, true);
    w.applyWeatherMarkerUpdates([{ icao: 'EHAM', fcat: 'VFR' }]);
    assert.equal(popup.querySelector('[data-channel="Tower"]').getAttribute('aria-pressed'), 'false');
    assert.equal(popup.querySelector('[data-channel="Approach"]').getAttribute('aria-pressed'), 'true');
    sync(['Approach']); assert.equal(m.isFav, true);
    sync([]); assert.equal(m.isFav, false); assert.equal(item.cat, 'vfr');
    // Reopen from canonical data, as Leaflet does after a rebuild.
    popup.innerHTML = w.buildMarkerPopupHtml(m, item.color);
    assert.equal(popup.querySelector('.airport-favorite-link').getAttribute('aria-pressed'), 'false');
    assert.equal(popup.querySelectorAll('.active').length, 0);
}
const confirmed = JSON.stringify(m);
w.syncCurrentFavoriteControl({ ok: false, favorites: [favorite('Tower')] });
assert.equal(JSON.stringify(m), confirmed);
assert.ok(filters >= 15);
console.log('Map favorites DOM regression tests passed.');
