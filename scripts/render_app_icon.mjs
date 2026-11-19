import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { Resvg } from '@resvg/resvg-js';

const root = resolve(import.meta.dirname, '..');
const source = resolve(root, 'assets/icons/bpb_icon.svg');
const output = resolve(root, 'assets/icons/ic_stat_vpn.png');
const svg = readFileSync(source, 'utf8');
const rendered = new Resvg(svg, {
  fitTo: { mode: 'width', value: 256 },
}).render();
writeFileSync(output, rendered.asPng());
console.log(`Rendered transparent BPB icon: ${output}`);
