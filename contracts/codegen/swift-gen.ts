/**
 * Generates Swift Codable structs from zod schemas.
 * Run: npx tsx codegen/swift-gen.ts
 * Output: ../ios/core/contracts/
 */

import * as fs from 'fs';
import * as path from 'path';

const OUTPUT_DIR = path.resolve(__dirname, '../../ios/core/contracts');

function main() {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });

  // Placeholder — real implementation will introspect zod schemas
  // and generate Swift Codable structs automatically
  console.log('Swift codegen: placeholder — implement schema introspection');
  console.log(`Output dir: ${OUTPUT_DIR}`);
}

main();
