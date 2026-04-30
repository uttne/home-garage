import { cpSync } from 'node:fs';
import { relative, sep } from 'node:path';

export function copyWorkingTree(sourceRoot: string, destinationRoot: string): void {
  const ignoredTopLevelEntries = new Set(['.git', 'node_modules', '.tmp']);

  cpSync(sourceRoot, destinationRoot, {
    recursive: true,
    filter: (source) => {
      const rel = relative(sourceRoot, source);
      if (!rel) {
        return true;
      }

      const firstSegment = rel.split(sep)[0];
      return !ignoredTopLevelEntries.has(firstSegment);
    },
  });
}
