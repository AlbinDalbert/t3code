import { describe, expect, it } from "vitest";

import { toWorkspaceRelativePath } from "./workspaceRelativePath";

describe("toWorkspaceRelativePath", () => {
  it("converts absolute paths inside the workspace root to relative paths", () => {
    expect(
      toWorkspaceRelativePath("/workspace/t3code/apps/web/src/App.tsx", "/workspace/t3code"),
    ).toBe("apps/web/src/App.tsx");
  });

  it("converts Windows absolute paths inside the workspace root to relative paths", () => {
    expect(
      toWorkspaceRelativePath("C:/Users/julius/project/src/main.ts", "C:\\Users\\julius\\project"),
    ).toBe("src/main.ts");
  });

  it("keeps already relative paths relative", () => {
    expect(toWorkspaceRelativePath("./src/main.ts", "/workspace/t3code")).toBe("src/main.ts");
  });

  it("drops line and column suffixes", () => {
    expect(toWorkspaceRelativePath("/workspace/t3code/src/main.ts:12:4", "/workspace/t3code")).toBe(
      "src/main.ts",
    );
  });
});
