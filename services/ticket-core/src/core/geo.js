// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

/** Ray casting. `ring` is [[lon, lat], …]; the closing point may be left out. */
export function pointInRing(lon, lat, ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i];
    const [xj, yj] = ring[j];
    if ((yi > lat) !== (yj > lat) && lon < ((xj - xi) * (lat - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

export function distanceMeters(a, b) {
  const rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad;
  const dLon = (b.lon - a.lon) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) ** 2;
  return 12742000 * Math.asin(Math.sqrt(h));
}

// Rough outlines for stops that carry no country. Good enough to tell Linz from Munich, not good enough at a
// border: results that rest on them are marked "approximate". Operators' own stop lists replace them.
export const ROUGH_COUNTRIES = {
  AT: [[9.53, 47.27], [9.6, 47.06], [10.1, 46.85], [10.47, 46.86], [11.0, 46.77], [11.5, 47.0], [12.2, 47.08],
    [12.4, 46.69], [13.7, 46.52], [14.55, 46.38], [15.0, 46.62], [15.65, 46.7], [16.0, 46.67], [16.1, 46.87],
    [16.5, 47.0], [16.45, 47.4], [16.65, 47.6], [17.16, 48.0], [16.95, 48.6], [16.1, 48.75], [15.0, 49.02],
    [14.7, 48.6], [13.83, 48.77], [13.4, 48.37], [12.75, 48.12], [13.0, 47.85], [12.9, 47.72], [12.78, 47.67],
    [12.2, 47.6], [11.6, 47.58], [11.0, 47.4], [10.45, 47.57], [10.2, 47.28], [9.97, 47.55], [9.56, 47.54]],
  DE: [[6.1, 50.75], [5.9, 51.05], [6.2, 51.85], [6.7, 51.9], [7.05, 52.25], [7.2, 53.25], [8.6, 54.9], [9.9, 54.8],
    [11.0, 54.4], [12.5, 54.45], [14.2, 53.95], [14.4, 53.3], [14.15, 52.85], [14.75, 52.1], [14.6, 51.8],
    [15.03, 51.25], [14.3, 51.05], [14.3, 50.9], [12.5, 50.4], [12.1, 50.3], [12.5, 49.9], [13.83, 48.77],
    [13.4, 48.37], [12.75, 48.12], [13.0, 47.85], [12.9, 47.72], [13.08, 47.47], [12.78, 47.67], [12.2, 47.6],
    [11.6, 47.58], [11.0, 47.4], [10.45, 47.57], [10.2, 47.28], [9.97, 47.55], [9.56, 47.54], [8.6, 47.8],
    [7.6, 47.58], [7.55, 48.1], [8.2, 48.97], [6.75, 49.17], [6.37, 49.47], [6.1, 50.1]],
};

/** { code, approximate } for a stop, or null when nothing tells. */
export function stopCountry(stop) {
  if (!stop) return null;
  if (typeof stop.country === "string" && /^[A-Za-z]{2}$/.test(stop.country)) {
    return { code: stop.country.toUpperCase(), approximate: false };
  }
  // Transitous stop ids start with the feed's country, e.g. "de-DELFI_de:09162:6".
  const prefix = /^([a-z]{2})[-_]/.exec(stop.stopId ?? "");
  if (prefix) return { code: prefix[1].toUpperCase(), approximate: false };
  if (typeof stop.lat === "number" && typeof stop.lon === "number") {
    for (const [code, ring] of Object.entries(ROUGH_COUNTRIES)) {
      if (pointInRing(stop.lon, stop.lat, ring)) return { code, approximate: true };
    }
  }
  return null;
}
