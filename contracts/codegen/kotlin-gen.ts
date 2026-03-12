/**
 * Generates Kotlin data classes from zod schemas.
 * Run: npx tsx codegen/kotlin-gen.ts
 * Output: ../android/core/contracts/
 */

import * as fs from 'fs';
import * as path from 'path';

const OUTPUT_DIR = path.resolve(__dirname, '../../android/core/contracts');

function main() {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });

  // Placeholder — real implementation will introspect zod schemas
  // and generate Kotlin data classes automatically
  console.log('Kotlin codegen: placeholder — implement schema introspection');
  console.log(`Output dir: ${OUTPUT_DIR}`);
}

main();
