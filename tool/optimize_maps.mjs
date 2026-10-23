// Rebuilds assets/maps3d/*.glb from ../3D Map/models. Needs: npm i @gltf-transform/core @gltf-transform/extensions
// @gltf-transform/functions meshoptimizer sharp.  Run: node tool/optimize_maps.mjs "../3D Map/models" assets/maps3d [map ids...]
// Shrinks the 3D Map GLBs for the game: drops the Fighters group (the game draws its own pieces),
// dedups/prunes, converts textures to WebP and compresses geometry with meshopt.
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { dedup, prune, textureCompress, meshopt, weld, resample } from '@gltf-transform/functions';
import { MeshoptEncoder, MeshoptDecoder } from 'meshoptimizer';
import sharp from 'sharp';
import fs from 'node:fs';
import path from 'node:path';

const [inDir, outDir, ...only] = process.argv.slice(2);
await MeshoptEncoder.ready; await MeshoptDecoder.ready;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({ 'meshopt.encoder': MeshoptEncoder, 'meshopt.decoder': MeshoptDecoder });
for (const f of fs.readdirSync(inDir).filter(f => f.endsWith('.glb'))) {
  const id = f.replace('unmatched-', '').replace('.glb', '');
  if (only.length && !only.includes(id)) continue;
  const doc = await io.read(path.join(inDir, f));
  for (const n of doc.getRoot().listNodes()) {
    if (n.getName() === 'Fighters') { for (const c of n.listChildren()) c.dispose(); n.dispose(); }
  }
  await doc.transform(
    dedup(), prune(), weld(),
    textureCompress({ encoder: sharp, targetFormat: 'webp', quality: 82, resize: [4096, 4096] }),
    meshopt({ encoder: MeshoptEncoder, level: 'medium' }),
  );
  const out = path.join(outDir, id + '.glb');
  await io.write(out, doc);
  console.log(id, (fs.statSync(path.join(inDir, f)).size / 1e6).toFixed(1), '->', (fs.statSync(out).size / 1e6).toFixed(1), 'MB');
}
