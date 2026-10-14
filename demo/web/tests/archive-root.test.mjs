import assert from "node:assert/strict";
import { register } from "node:module";
import { pathToFileURL } from "node:url";
import path from "node:path";

register("./cdn-loader.mjs", import.meta.url, { data: { url: process.env.ANYPS5_TEST_ZIP_URL, path: process.env.ANYPS5_TEST_ZIP_PATH } });
const { Archive } = await import(pathToFileURL(path.join(process.argv[2], "archive.mjs")));
const { BlobWriter, Uint8ArrayReader, ZipWriter } = await import(process.env.ANYPS5_TEST_ZIP_URL);
const header = new Uint8Array([127, 69, 76, 70]);

async function zipped(entries) {
  const writer = new ZipWriter(new BlobWriter(), { useWebWorkers: false, useCompressionStream: false });
  for (const [name, directory] of entries) await writer.add(name, directory ? undefined : new Uint8ArrayReader(header), { directory });
  return writer.close();
}

const parents = ["outer/", "outer/inner/", "outer/inner/title/"];
for (const directories of [[], parents, [...parents].reverse()]) {
  const archive = new Archive(await zipped([
    ...directories.map(name => [name, true]), ["outer/inner/title/main.elf", false]
  ]));
  try {
    const summary = await archive.inspect(() => {});
    assert.equal(summary.root, "outer/inner/title/");
    assert.equal(summary.name, "main.elf");
    assert.equal(summary.files, 1);
    assert.deepEqual((await archive.conversionInput("linux", false, () => {})).executable, header);
  } finally { await archive.close(); }
}

const folder = new Archive([{ path: "outer/inner/title/main.elf", file: new Blob([header]) }]);
try { assert.equal((await folder.inspect(() => {})).root, "outer/inner/title/"); }
finally { await folder.close(); }

const siblings = new Archive(await zipped([["outer/", true], ["outer/main.elf", false], ["other/resource", false]]));
try { await assert.rejects(siblings.inspect(() => {}), /exactly one executable ELF/); }
finally { await siblings.close(); }
