import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { FalAnimations, ANIMATIONS } from './animations.js';

// Run from backend: node --env-file-if-exists=.env generate-animations.js INPUT.png OUTPUT_DIR [playful|run|sleep|idle]
const [input, output, selected] = process.argv.slice(2);
if (!input || !output || (selected && !Object.hasOwn(ANIMATIONS, selected))) {
  console.error('Usage: generate-animations.js INPUT.png OUTPUT_DIR [playful|run|sleep|idle]'); process.exit(1);
}
const animations = new FalAnimations(process.env.FAL_KEY, resolve(output));
const pet = { id: 'pet', image: (await readFile(resolve(input))).toString('base64') };
for (const kind of selected ? [selected] : Object.keys(ANIMATIONS)) {
  console.log(`Preparing ${kind} animation…`);
  try {
    const result = await animations.generate(kind, pet);
    console.log(`${kind}: ${result.frameCount} RGBA frames, ${result.width}×${result.height}, ${result.fps} FPS.`);
  } catch (error) { console.error(error.message); process.exitCode = 1; break; }
}
