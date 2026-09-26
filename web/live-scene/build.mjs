// Bundles the live-scene page into the app: App/LiveScene/Web/{live-scene.html,
// live-scene.js, reactor_wasm_bg.wasm}. The app's SceneSchemeHandler serves these
// at popscene://app/…. Run `npm run build` after changing anything in src/.
import { build } from "esbuild";
import { copyFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const here = (path) => fileURLToPath(new URL(path, import.meta.url));
const outDir = here("../../App/LiveScene/Web/");

await mkdir(outDir, { recursive: true });

await build({
  entryPoints: [here("src/main.ts")],
  outfile: `${outDir}live-scene.js`,
  bundle: true,
  format: "esm",
  target: ["safari18"],
  minify: true,
  legalComments: "eof",
  define: { "process.env.NODE_ENV": '"production"' },
  logLevel: "info",
});

await copyFile(here("live-scene.html"), `${outDir}live-scene.html`);
await copyFile(
  here("node_modules/@reactor-team/js-sdk/dist/wasm/reactor_wasm_bg.wasm"),
  `${outDir}reactor_wasm_bg.wasm`,
);
