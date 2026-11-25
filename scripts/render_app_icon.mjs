import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { Resvg } from '@resvg/resvg-js';

const root = resolve(import.meta.dirname, '..');
const source = resolve(root, 'assets/icons/bpb_icon.svg');
const output = resolve(root, 'assets/icons/ic_stat_vpn.png');
const connectedOutput = resolve(root, 'assets/icons/ic_stat_vpn_connected.png');
const svg = readFileSync(source, 'utf8');

function renderIcon(markup, destination) {
  const rendered = new Resvg(markup, {
    fitTo: { mode: 'width', value: 256 },
  }).render();
  writeFileSync(destination, rendered.asPng());
  console.log(`Rendered Windows shell icon: ${destination}`);
}

const connectedSvg = svg
  .replaceAll('#168BFF', '#32D96B')
  .replaceAll('#62C8FF', '#8BFFAD');
if (connectedSvg === svg) {
  throw new Error('Could not create connected icon: expected blue icon colors were not found.');
}

renderIcon(svg, output);
renderIcon(connectedSvg, connectedOutput);
