import { splitPathAndPosition } from "./terminal-links";

function normalizePathSeparators(path: string): string {
  return path.replaceAll("\\", "/");
}

function canonicalizeWindowsDrivePath(path: string): string {
  return /^\/[A-Za-z]:\//.test(path) ? path.slice(1) : path;
}

function trimTrailingPathSeparators(path: string): string {
  return path.replace(/[\\/]+$/, "");
}

function stripRelativePrefix(path: string): string {
  return path.replace(/^\.\/+/, "");
}

export function toWorkspaceRelativePath(pathWithPosition: string, workspaceRoot?: string): string {
  const { path } = splitPathAndPosition(pathWithPosition);
  const normalizedPath = canonicalizeWindowsDrivePath(normalizePathSeparators(path.trim()));
  if (!workspaceRoot) {
    return stripRelativePrefix(normalizedPath);
  }

  const normalizedWorkspaceRoot = canonicalizeWindowsDrivePath(
    normalizePathSeparators(trimTrailingPathSeparators(workspaceRoot.trim())),
  );
  const pathForCompare = normalizedPath.toLowerCase();
  const workspaceForCompare = normalizedWorkspaceRoot.toLowerCase();
  const workspaceWithSeparator = `${workspaceForCompare}/`;

  if (pathForCompare.startsWith(workspaceWithSeparator)) {
    return normalizedPath.slice(normalizedWorkspaceRoot.length + 1);
  }

  return stripRelativePrefix(normalizedPath);
}
