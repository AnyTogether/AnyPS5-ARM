import { BlobReader, Uint8ArrayReader, ZipReader, ZipWriter, configure } from "https://cdn.jsdelivr.net/npm/@zip.js/zip.js@2.7.57/lib/zip-no-worker.js/+esm";

configure({ useWebWorkers: false, useCompressionStream: false, chunkSize: 65536 });

export const MEMORY_LIMIT = 256 * 1024 * 1024;
export const CONVERSION_LIMIT = 256 * 1024 * 1024;
export const ICON_LIMIT = 16 * 1024 * 1024;
const MAX_ENTRIES = 100000;

class BoundedBlobReader extends BlobReader {
  async readUint8Array(offset, length) {
    if (length > 16 * 1024 * 1024) throw new Error("ZIP directory metadata exceeds 16 MiB");
    return super.readUint8Array(offset, length);
  }
}


export function validPath(name) {
  if (!name || name.includes("\\") || /[\x00-\x1f<>:"|?*]/u.test(name)) throw new Error(`Unsafe ZIP path: ${name}`);
  const parts = name.replace(/\/$/u, "").split("/");
  if (parts.some(part => !part || part === "." || part === ".." || /[. ]$/u.test(part) || /^(con|prn|aux|nul|com[1-9\u00b9\u00b2\u00b3]|lpt[1-9\u00b9\u00b2\u00b3])(?:\.|$)/iu.test(part))) throw new Error(`Unsafe ZIP path: ${name}`);
  return name;
}

function safeSize(value) {
  if (!Number.isSafeInteger(value) || value < 0) throw new Error("ZIP contains an unsupported file size");
  return value;
}

async function signature(entry) {
  if (entry.uncompressedSize < 4) return false;
  const stop = new AbortController();
  const header = new Uint8Array(4);
  let filled = 0;
  try {
    await entry.getData(new WritableStream({
      write(chunk) {
        const length = Math.min(4 - filled, chunk.length);
        header.set(chunk.subarray(0, length), filled);
        filled += length;
        if (filled === 4) stop.abort();
      }
    }), { signal: stop.signal, checkSignature: false });
  } catch (error) {
    if (!stop.signal.aborted || filled !== 4) throw error;
  }
  return header[0] === 0x7f && header[1] === 69 && header[2] === 76 && header[3] === 70;
}

async function boundedBytes(entry, limit) {
  if (entry.uncompressedSize > limit) throw new Error(`${entry.filename} exceeds the conversion memory limit`);
  let size = 0;
  const chunks = [];
  await entry.getData(new WritableStream({
    write(chunk) {
      size += chunk.byteLength;
      if (size > limit || size > entry.uncompressedSize) throw new Error(`Unexpected expanded size: ${entry.filename}`);
      chunks.push(chunk);
    }
  }), { checkSignature: true });
  if (size !== entry.uncompressedSize) throw new Error(`Incorrect expanded size: ${entry.filename}`);
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return bytes;
}

class FolderReader {
  constructor(files) {
    this.files = files;
  }

  async *getEntriesGenerator() {
    for (const { path, file } of this.files) {
      if (!(file instanceof Blob)) throw new Error(`Invalid folder file: ${path}`);
      yield {
        filename: path, uncompressedSize: file.size, directory: false, compressionMethod: 0,
        externalFileAttributes: (0o100644 << 16) >>> 0,
        getData(destination, options = {}) {
          return file.stream().pipeTo(destination, { signal: options.signal });
        }
      };
    }
  }

  async close() {}
}

export class Archive {
  constructor(file) {
    this.reader = Array.isArray(file) ? new FolderReader(file) : new ZipReader(new BoundedBlobReader(file));
    this.entries = [];
  }

  async inspect(report) {
    const paths = new Map();
    let total = 0;
    for await (const entry of this.reader.getEntriesGenerator()) {
      if (this.entries.length >= MAX_ENTRIES) throw new Error("Input contains more than 100,000 entries");
      validPath(entry.filename);
      const key = entry.filename.replace(/\/$/u, "").toLowerCase();
      if (paths.has(key)) throw new Error(`Duplicate ZIP path: ${entry.filename}`);
      if (entry.encrypted) throw new Error(`Encrypted ZIP entries are not supported: ${entry.filename}`);
      if (!entry.directory && entry.compressionMethod !== 0 && entry.compressionMethod !== 8) throw new Error(`Unsupported ZIP compression: ${entry.filename}`);
      const mode = (entry.externalFileAttributes >>> 16) & 0xf000;
      if (mode && mode !== 0x8000 && mode !== 0x4000) throw new Error(`Links and special files are not supported: ${entry.filename}`);
      paths.set(key, entry.directory);
      total = safeSize(total + safeSize(entry.uncompressedSize));
      this.entries.push(entry);
    }
    if (!this.entries.some(entry => !entry.directory)) throw new Error("No files were selected");
    for (const entry of this.entries) {
      const parts = entry.filename.split("/");
      for (let index = 1; index < parts.length; index++) {
        if (paths.get(parts.slice(0, index).join("/").toLowerCase()) === false) throw new Error(`A file is also used as a folder: ${entry.filename}`);
      }
    }
    let prefix = "";
    const files = this.entries.filter(entry => !entry.directory);
    while (files.every(entry => entry.filename.slice(prefix.length).includes("/"))) {
      const first = files[0].filename.slice(prefix.length).split("/")[0];
      if (["sce_sys", "sce_module"].includes(first) || !this.entries.every(entry => (entry.directory && prefix.startsWith(entry.filename)) || entry.filename.startsWith(prefix + first + "/"))) break;
      prefix += first + "/";
    }
    this.prefix = prefix;
    this.files = this.entries.filter(entry => entry.filename.startsWith(prefix) && entry.filename !== prefix).map(entry => ({ entry, name: entry.filename.slice(prefix.length) }));
    const executables = [];
    this.modules = [];
    for (let index = 0; index < this.files.length; index++) {
      const item = this.files[index];
      report({ phase: "Inspecting files", input: item.name, completed: index, total: this.files.length });
      if (item.entry.directory || item.name.startsWith("sce_sys/")) continue;
      if (!item.name.startsWith("sce_module/") && item.name.includes("/")) continue;
      if (item.name.startsWith("sce_module/") && item.name.endsWith(".guest.prx")) continue;
      const elf = await signature(item.entry);
      if (item.name.startsWith("sce_module/")) {
        if (elf) this.modules.push(item);
      } else if (elf) executables.push(item);
    }
    if (executables.length !== 1) throw new Error(`Expected exactly one executable ELF in the app root; found ${executables.length}`);
    this.executable = executables[0];
    if (this.executable.name.includes("/")) throw new Error("Place the executable next to sce_sys and sce_module, not inside another folder");
    this.icon = this.files.find(item => item.name === "sce_sys/icon0.png" && !item.entry.directory);
    this.selectedBytes = [this.executable, ...this.modules].reduce((sum, item) => sum + item.entry.uncompressedSize, 0);
    this.windowsSelectedBytes = this.selectedBytes + (this.icon?.entry.uncompressedSize ?? 0);
    if (this.selectedBytes > CONVERSION_LIMIT) throw new Error("Executable and modules exceed the 256 MiB conversion limit. Use the native relinker for this app.");
    const warnings = [];
    if (!this.files.some(item => item.name.startsWith("sce_sys/"))) warnings.push("sce_sys is missing. The Windows executable will have no app icon.");
    else if (!this.icon) warnings.push("sce_sys/icon0.png is missing. The Windows executable will have no app icon.");
    if (!this.files.some(item => item.name.startsWith("sce_module/"))) warnings.push("sce_module is missing. If the original app included this folder, leaving it out can prevent the app from starting.");
    this.totalBytes = total;
    return { name: this.executable.name, files: files.length, modules: this.modules.length, totalBytes: total, selectedBytes: this.selectedBytes, windowsSelectedBytes: this.windowsSelectedBytes, windowsIconTooLarge: (this.icon?.entry.uncompressedSize ?? 0) > ICON_LIMIT, root: prefix, warnings };
  }

  selectedBytesForTarget(target) {
    if (target !== "linux" && target !== "windows") throw new Error(`Unsupported conversion target: ${target}`);
    if (target === "windows" && (this.icon?.entry.uncompressedSize ?? 0) > ICON_LIMIT) throw new Error("sce_sys/icon0.png exceeds 16 MiB");
    return target === "windows" ? this.windowsSelectedBytes : this.selectedBytes;
  }

  async conversionInput(target, toIntel, report) {
    let remaining = CONVERSION_LIMIT;
    const selectedBytes = this.selectedBytesForTarget(target);
    if (selectedBytes > CONVERSION_LIMIT) throw new Error(`Selected ${target} conversion input exceeds the 256 MiB conversion limit. Use the native relinker for this app.`);
    const read = async item => {
      report({ phase: "Reading conversion input", input: item.name });
      const bytes = await boundedBytes(item.entry, remaining);
      remaining -= bytes.length;
      return bytes;
    };
    const name = this.executable.name;
    const stem = name.includes(".") ? name.slice(0, name.lastIndexOf(".")) : name;
    const outputName = (stem || "app") + (target === "windows" ? ".exe" : ".elf");
    const input = { name, outputName, target, toIntel, executable: await read(this.executable), modules: [], icon: null };
    for (const item of this.modules) input.modules.push({ name: item.name, bytes: await read(item) });
    if (this.icon && target === "windows") input.icon = await read(this.icon);
    return input;
  }

  async close() { await this.reader.close(); }
}

export function memoryEstimate(archiveBytes, selectedBytes, libraryBytes, entries) {
  return safeSize(Math.ceil(archiveBytes * 1.02) + selectedBytes * 4 + libraryBytes + entries * 1024 + 8 * 1024 * 1024);
}

async function appendEntry(writer, name, entry, report) {
  const stream = new TransformStream();
  let produced = 0;
  const limit = new TransformStream({ transform(chunk, controller) {
    produced += chunk.length;
    if (produced > entry.uncompressedSize) throw new Error(`Unexpected expanded size: ${name}`);
    controller.enqueue(chunk);
  }, flush() {
    if (produced !== entry.uncompressedSize) throw new Error(`Incorrect expanded size: ${name}`);
  } });
  await Promise.all([
    entry.getData(stream.writable, { checkSignature: true }),
    writer.add(name, stream.readable.pipeThrough(limit), {
      versionMadeBy: 0x31e, externalFileAttributes: entry.externalFileAttributes,
      onprogress: completed => report({ phase: writer instanceof DirectoryWriter ? "Writing files" : "Compressing ZIP", input: name, completed, total: entry.uncompressedSize })
    })
  ]);
}

class DirectoryWriter {
  constructor(destination) {
    this.destination = destination;
  }

  async add(name, source, options = {}) {
    if (options.directory) {
      await this.destination.directory(name);
      return;
    }
    const output = await this.destination.file(name);
    if (source instanceof ReadableStream) {
      let completed = 0;
      const reader = source.getReader();
      const writer = output.getWriter();
      try {
        for (;;) {
          const { value, done } = await reader.read();
          if (done) break;
          for (let offset = 0; offset < value.length; offset += 65536) {
            const chunk = value.subarray(offset, offset + 65536);
            await writer.write(chunk);
            completed += chunk.length;
            options.onprogress?.(completed);
          }
        }
        await writer.close();
      } catch (error) {
        await reader.cancel(error);
        await writer.abort(error);
        throw error;
      } finally {
        reader.releaseLock();
        writer.releaseLock();
      }
    } else {
      await source.init();
      const writer = output.getWriter();
      try {
        for (let offset = 0; offset < source.size; offset += 65536) {
          await writer.write(await source.readUint8Array(offset, Math.min(65536, source.size - offset)));
        }
        await writer.close();
      } catch (error) {
        await writer.abort(error);
        throw error;
      } finally {
        writer.releaseLock();
      }
    }
  }

  async close() {}
}

export async function packageArchive(archive, converted, outputName, libraryFile, destination, report, directory = false) {
  const libraries = new ZipReader(new BoundedBlobReader(libraryFile));
  const writer = directory ? new DirectoryWriter(destination) : new ZipWriter(destination, { level: 9, zip64: true, bufferedWrite: false, useWebWorkers: false, useCompressionStream: false, preventClose: true });
  const names = new Set();
  const claim = name => {
    validPath(name);
    const key = name.replace(/\/$/u, "").toLowerCase();
    if (names.has(key)) throw new Error(`Output path collision: ${name}`);
    names.add(key);
  };
  try {
    const libraryEntries = await libraries.getEntries();
    if (!libraryEntries.length || libraryEntries.length > 4096) throw new Error("Invalid library archive");
    for (const entry of libraryEntries) {
      if (!entry.filename.startsWith("libs/") || entry.encrypted || ((entry.externalFileAttributes >>> 16) & 0xf000) === 0xa000) throw new Error("Invalid library archive layout");
      claim(entry.filename);
    }
    const replaced = new Set(converted.modules.map(module => module.name));
    const originalFiles = archive.files.filter(item => !replaced.has("app0/" + item.name));
    for (const item of originalFiles) claim("app0/" + item.name);
    claim(outputName);
    if (converted.diagnostics) claim("windows-diagnostics-imports.txt");
    for (const module of converted.modules) {
      if (!module.name.startsWith("app0/sce_module/")) throw new Error("Invalid converted module path");
      claim(module.name);
    }
    const binary = { versionMadeBy: 0x31e, externalFileAttributes: (0o100755 << 16) >>> 0 };
    await writer.add(outputName, new Uint8ArrayReader(converted.executable), binary);
    if (converted.diagnostics) await writer.add("windows-diagnostics-imports.txt", new Uint8ArrayReader(new TextEncoder().encode(converted.diagnostics)));
    for (const module of converted.modules) await writer.add(module.name, new Uint8ArrayReader(module.bytes), binary);
    for (const entry of libraryEntries) {
      if (entry.directory) await writer.add(entry.filename, undefined, { directory: true });
      else await appendEntry(writer, entry.filename, entry, report);
    }
    for (const { entry, name } of originalFiles) {
      if (entry.directory) await writer.add("app0/" + name, undefined, { directory: true });
      else await appendEntry(writer, "app0/" + name, entry, report);
    }
    await writer.close();
  } finally {
    await libraries.close();
  }
}
