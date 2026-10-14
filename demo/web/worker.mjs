import { Archive, CONVERSION_LIMIT, MEMORY_LIMIT, memoryEstimate, packageArchive } from "./archive.mjs";

let archive;
let busy = false;
let pendingWrite;
let lastReport = 0;
let lastPhase = "";

function report(event) {
  const phase = event.phase ?? String(event.stage);
  const now = performance.now();
  if (!event.message && phase === lastPhase && event.completed !== event.total && now - lastReport < 80) return;
  lastReport = now;
  lastPhase = phase;
  self.postMessage({ type: "progress", ...event });
}

export async function downloadLibraries(target) {
  report({ phase: "Downloading system libraries" });
  const response = await fetch("./release.json", { cache: "no-cache" });
  if (!response.ok) throw new Error(`Cannot load release manifest (${response.status})`);
  const release = await response.json();
  const asset = release.platforms[target];
  if (!asset || !/^libraries\/(windows|linux)-[a-f0-9]+\.zip$/u.test(asset.path) || !/^[a-f0-9]{64}$/u.test(asset.sha256)) throw new Error("Invalid release manifest");
  const latestResponse = await fetch("https://api.github.com/repos/boykopovar/AnyPS5/releases/latest", { headers: { Accept: "application/vnd.github+json" } });
  if (!latestResponse.ok) {
    const rateLimited = latestResponse.status === 429 || (latestResponse.status === 403 && latestResponse.headers.get("x-ratelimit-remaining") === "0");
    if (!rateLimited) throw new Error(`Cannot verify the latest release (${latestResponse.status}). Try again later.`);
    report({ phase: "Downloading system libraries", message: "GitHub API rate limit reached; using the libraries published with this site." });
  } else {
    const latest = await latestResponse.json();
    if (latest.tag_name !== release.tag) throw new Error("A new release is being published to this site. Try again after the Pages build finishes.");
  }
  const download = await fetch(asset.path);
  if (!download.ok) throw new Error(`Cannot download system libraries (${download.status})`);
  const bytes = await download.arrayBuffer();
  if (bytes.byteLength !== asset.size) throw new Error("System library download is incomplete");
  const digest = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(byte => byte.toString(16).padStart(2, "0")).join("");
  if (digest !== asset.sha256) throw new Error("System library checksum mismatch");
  return { file: new Blob([bytes]), release, expandedBytes: asset.expandedBytes };
}

self.onmessage = async ({ data }) => {
  if (data.type === "written") {
    if (!pendingWrite) return;
    const resolve = pendingWrite;
    pendingWrite = null;
    resolve();
    return;
  }
  if (busy) return;
  busy = true;
  try {
    if (data.type === "inspect") {
      if (archive) await archive.close();
      archive = new Archive(data.files ?? data.file);
      const summary = await archive.inspect(report);
      self.postMessage({ type: "inspected", summary });
    } else if (data.type === "convert") {
      if (data.target === "windows" && data.mode === "disk") throw new Error("Windows folder output is unavailable because browsers block DLL creation. Choose a ZIP save mode.");
      if (!archive) throw new Error("Select a ZIP or folder first");
      const selectedBytes = archive.selectedBytesForTarget(data.target);
      if (selectedBytes > CONVERSION_LIMIT) throw new Error(`Selected ${data.target} conversion input exceeds the 256 MiB conversion limit. Use the native relinker for this app.`);
      const libraries = await downloadLibraries(data.target);
      const estimate = memoryEstimate(archive.totalBytes, selectedBytes, libraries.expandedBytes, archive.entries.length);
      if (data.mode === "memory" && estimate > MEMORY_LIMIT) throw new Error("This result exceeds the 256 MiB memory-download budget. Use Save ZIP to disk in desktop Chrome or Edge.");
      report({ phase: "Loading converter" });
      const { default: createRelinker } = await import("./native/relinker_wasm.mjs");
      const native = await createRelinker();
      let input = await archive.conversionInput(data.target, data.toIntel, report);
      const outputName = input.outputName;
      const converted = native.Convert(input, report);
      input = null;
      if (!converted.ok) throw new Error(converted.error);
      const chunks = [];
      let size = 0;
      const send = (event, transfer = []) => new Promise(resolve => {
        pendingWrite = resolve;
        self.postMessage(event, transfer);
      });
      if (data.mode === "disk") {
        const destination = {
          directory: name => send({ type: "directory", name }),
          async file(name) {
            await send({ type: "open-file", name });
            return new WritableStream({
              async write(chunk) {
                size += chunk.byteLength;
                const bytes = chunk.slice();
                await send({ type: "write", bytes }, [bytes.buffer]);
              },
              close: () => send({ type: "close-file" })
            });
          }
        };
        await packageArchive(archive, converted, outputName, libraries.file, destination, report, true);
      } else if (data.mode === "memory" || data.mode === "zip") {
        const destination = new WritableStream({
          async write(chunk) {
            size += chunk.byteLength;
            if (data.mode === "zip") {
              const bytes = chunk.slice();
              await send({ type: "write", bytes }, [bytes.buffer]);
              return;
            }
            if (size > MEMORY_LIMIT) throw new Error("The compressed ZIP exceeded 256 MiB. Use Save ZIP to disk.");
            chunks.push(chunk.slice());
          }
        });
        await packageArchive(archive, converted, outputName, libraries.file, destination, report);
        await destination.close();
      } else throw new Error("Unknown save mode");
      self.postMessage({ type: "complete", mode: data.mode, blob: data.mode === "memory" ? new Blob(chunks, { type: "application/zip" }) : null, outputName, size, release: libraries.release.tag });
      await archive.close();
      archive = null;
    } else throw new Error("Unknown worker request");
  } catch (error) {
    self.postMessage({ type: "error", message: error instanceof Error ? error.message : String(error) });
  } finally {
    busy = false;
  }
};
