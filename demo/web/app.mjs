const $ = id => document.getElementById(id);
const stages = ["Converting executable", "Converting PRX modules", "Scanning syscalls", "Scanning instructions", "Converting instructions", "Analysing imports", "Building output image", "Writing output"];
let worker;
let file;
let summary;
let working = false;
let sink;
let outputDirectory;
let downloadUrl;
let logs = [];
let release;
const canSaveZip = typeof window.showSaveFilePicker === "function" && window.isSecureContext;
const canStream = typeof window.showDirectoryPicker === "function" && window.isSecureContext;
const supported = window.isSecureContext && window.Worker && window.WebAssembly && window.ReadableStream && window.WritableStream && window.crypto?.subtle;
$("save").querySelector('[value="disk"]').disabled = !canStream;
$("save").querySelector('[value="zip"]').disabled = !canSaveZip;
$("save").value = canSaveZip ? "zip" : "memory";

function bytes(value) {
  if (value < 1024) return `${value} B`;
  const unit = value >= 1024 ** 3 ? 3 : value >= 1024 ** 2 ? 2 : 1;
  return `${(value / 1024 ** unit).toFixed(1)} ${["B", "KiB", "MiB", "GiB"][unit]}`;
}

function update() {
  const target = document.querySelector('input[name="target"]:checked').value;
  const folderBlocked = target === "windows" && $("save").value === "disk";
  const folderOption = $("save").querySelector('[value="disk"]');
  folderOption.disabled = !canStream || target === "windows";
  folderOption.textContent = target === "windows" ? "Save to folder · unavailable for Windows (DLL restrictions)" : "Save to folder · uncompressed";
  const libraryBytes = release?.platforms[target]?.expandedBytes;
  const selectedBytes = summary ? target === "windows" ? summary.windowsSelectedBytes : summary.selectedBytes : null;
  const conversionTooLarge = selectedBytes !== null && selectedBytes > 256 * 1024 * 1024;
  const iconTooLarge = target === "windows" && Boolean(summary?.windowsIconTooLarge);
  const conversionBlocked = conversionTooLarge || iconTooLarge;
  const estimate = summary && libraryBytes !== undefined ? Math.ceil(summary.totalBytes * 1.02) + selectedBytes * 4 + libraryBytes + summary.files * 1024 + 8 * 1024 * 1024 : null;
  const tooLarge = estimate !== null && estimate > 256 * 1024 * 1024;
  $("save").querySelector('[value="memory"]').disabled = Boolean(tooLarge);
  const memoryBlocked = $("save").value === "memory" && tooLarge;
  if (summary) $("archive-info").textContent = `${summary.files} files · ${bytes(summary.totalBytes)} expanded · ${summary.modules} modules · ${bytes(selectedBytes)} ${target} conversion input` + (summary.root ? ` · Root: ${summary.root}` : "");
  $("save-note").textContent = $("save").value === "disk" ? "Creates a subfolder with the executable, libs and app0. No ZIP compression. Browsers may block DLL and other restricted files; use ZIP for those apps." : $("save").value === "zip" ? "Writes a compressed ZIP directly to disk without holding the whole archive in memory." : "Up to 256 MiB including expanded files and output overhead.";
  $("browser-note").hidden = supported && canStream && canSaveZip && !memoryBlocked && !folderBlocked && !conversionBlocked;
  $("browser-note").textContent = !supported ? "This browser or connection does not support the converter. Use a current browser over HTTPS, or use the native relinker." : folderBlocked ? "Browsers block direct DLL creation. Windows output requires ZIP. Choose Save ZIP to disk or Download in memory." : iconTooLarge ? "The Windows icon exceeds 16 MiB. Choose Linux or use the native relinker." : conversionTooLarge ? `This ${target} conversion input exceeds 256 MiB. Use the native relinker for this app.` : memoryBlocked ? "This archive exceeds the memory-download limit. Choose Save ZIP to disk. If that option is unavailable, open this page in desktop Chrome or Edge." : "Some direct disk saving options are unavailable in this browser or context. Small apps can still be downloaded in memory. For larger apps, use desktop Chrome or Edge over HTTPS.";
  $("convert").disabled = !supported || working || !summary || !release || conversionBlocked || memoryBlocked || folderBlocked || (summary.warnings.length > 0 && !$("acknowledge").checked);
  $("ready-note").textContent = summary ? (folderBlocked ? "Choose a ZIP save mode for Windows." : iconTooLarge ? "The Windows icon exceeds 16 MiB. Choose Linux or use the native relinker." : conversionTooLarge ? `The ${target} conversion input exceeds 256 MiB. Use the native relinker.` : memoryBlocked ? "A direct disk save is required for this archive." : release ? `Libraries: ${release.tag} · ${$("save").value === "disk" ? "Uncompressed folder" : "ZIP compression level 9"}` : "Loading release information…") : "Choose a ZIP or folder to get started.";
}

function lock(value) {
  for (const id of ["choose", "choose-folder", "change", "target", "save", "intel"]) $(id).disabled = value || !supported || (id === "choose-folder" && !("webkitdirectory" in $("folder")));
}

async function fail(message) {
  worker?.terminate();
  worker = null;
  working = false;
  summary = null;
  if (sink) {
    const active = sink;
    sink = null;
    try { await active.abort(); } catch (error) { message += `\nCould not discard the output file: ${error.message}`; }
  }
  if (outputDirectory) { message += `\nIncomplete files remain in ${outputDirectory.name}/.`; outputDirectory = null; }
  $("error").textContent = message;
  $("error").hidden = false;
  $("status").hidden = true;
  $("cancel").hidden = true;
  $("drop").hidden = false;
  $("file").value = "";
  lock(false);
  update();
}

async function onMessage({ data }) {
  try {
    if (data.type === "progress") {
      if (data.message) {
        logs.push(data.message.trim());
        logs = logs.slice(-150);
        $("log").textContent = logs.join("\n");
        return;
      }
      $("phase").textContent = data.phase ?? stages[data.stage];
      $("current-file").textContent = data.input ?? "";
      if (Number.isFinite(data.total) && data.total > 0) {
        const percent = Math.min(100, Math.floor(data.completed / data.total * 100));
        $("progress").value = percent;
        $("percent").textContent = `${percent}%`;
      } else {
        $("progress").removeAttribute("value");
        $("percent").textContent = "";
      }
    } else if (data.type === "inspected") {
      summary = data.summary;
      working = false;
      $("selection").hidden = false;
      $("drop").hidden = true;
      $("archive-name").textContent = file.name;
      $("warning-list").replaceChildren(...summary.warnings.map(message => { const item = document.createElement("li"); item.textContent = message; return item; }));
      $("warnings").hidden = !summary.warnings.length;
      $("status").hidden = true;
      $("cancel").hidden = true;
      lock(false);
      update();
    } else if (data.type === "directory" || data.type === "open-file") {
      if (!outputDirectory) throw new Error("No output folder is open");
      const parts = data.name.replace(/\/$/u, "").split("/");
      if (parts.some(part => !part || part === "." || part === ".." || part.includes("\\"))) throw new Error("Invalid output path");
      const filename = data.type === "open-file" ? parts.pop() : null;
      let parent = outputDirectory;
      for (const part of parts) parent = await parent.getDirectoryHandle(part, { create: true });
      if (filename) {
        try {
          const handle = await parent.getFileHandle(filename, { create: true });
          sink = await handle.createWritable();
        } catch (error) {
          throw new Error(`Cannot write ${data.name}: ${error.message}. Choose ZIP output if the browser blocks this file type.`);
        }
      }
      worker?.postMessage({ type: "written" });
    } else if (data.type === "close-file") {
      if (!sink) throw new Error("No output file is open");
      await sink.close();
      sink = null;
      worker?.postMessage({ type: "written" });
    } else if (data.type === "write") {
      if (!sink) throw new Error("No output file is open");
      await sink.write(data.bytes);
      worker?.postMessage({ type: "written" });
    } else if (data.type === "complete") {
      if (sink) { await sink.close(); sink = null; }
      working = false;
      $("done").hidden = false;
      $("status").hidden = true;
      $("cancel").hidden = true;
      $("result-info").textContent = `${bytes(data.size)} ${data.mode === "disk" ? "files" : "ZIP"} · ${data.release} system libraries · ${data.outputName}`;
      if (data.blob) {
        downloadUrl = URL.createObjectURL(data.blob);
        $("download").href = downloadUrl;
        $("download").download = `${data.outputName}.zip`;
        $("download").hidden = false;
      } else if (data.mode === "zip") {
        $("result-info").textContent += " · ZIP saved to disk";
      } else {
        $("result-info").textContent += ` · Saved in ${outputDirectory.name}/`;
        if (document.querySelector('input[name="target"]:checked').value === "linux") $("result-info").textContent += ` · On Linux, run chmod +x "${data.outputName}" before launching.`;
      }
      $("result-note").hidden = data.mode === "disk";
      outputDirectory = null;
      summary = null;
      worker.terminate();
      worker = null;
      lock(false);
      update();
    } else if (data.type === "error") await fail(data.message);
  } catch (error) { await fail(error.message); }
}

async function selectFile(selected, files) {
  if (working || !supported || !selected) return;
  if (!files && !selected.name.toLowerCase().endsWith(".zip")) { await fail("Choose a ZIP archive."); return; }
  worker?.terminate();
  if (downloadUrl) { URL.revokeObjectURL(downloadUrl); downloadUrl = null; }
  summary = null;
  file = selected;
  working = true;
  logs = [];
  $("log").textContent = "";
  for (const id of ["error", "done", "download", "warnings", "selection"]) $(id).hidden = true;
  $("acknowledge").checked = false;
  $("status").hidden = false;
  $("cancel").hidden = false;
  $("phase").textContent = "Inspecting files";
  $("current-file").textContent = file.name;
  $("percent").textContent = "";
  $("progress").removeAttribute("value");
  lock(true);
  update();
  worker = new Worker(new URL("./worker.mjs", import.meta.url), { type: "module" });
  worker.onmessage = onMessage;
  worker.onerror = event => fail(event.message || "The converter worker stopped. Try a smaller app or use the native relinker.");
  worker.postMessage(files ? { type: "inspect", files } : { type: "inspect", file });
}

$("choose").onclick = () => $("file").click();
$("change").onclick = () => { $("drop").hidden = false; };
$("choose-folder").onclick = () => { $("folder").value = ""; $("folder").click(); };
$("folder").onchange = () => {
  const files = [...$("folder").files].map(file => ({ path: file.webkitRelativePath, file }));
  if (files.length) selectFile({ name: files[0].path.split("/")[0] }, files);
};
$("file").onchange = () => selectFile($("file").files[0]);
for (const type of ["dragenter", "dragover"]) $("drop").addEventListener(type, event => { event.preventDefault(); if (!working) $("drop").classList.add("dragging"); });
$("drop").ondragleave = () => $("drop").classList.remove("dragging");
$("drop").ondrop = event => { event.preventDefault(); $("drop").classList.remove("dragging"); if (working) return; if (event.dataTransfer.files.length !== 1) { fail("Drop one ZIP archive at a time."); return; } selectFile(event.dataTransfer.files[0]); };
for (const id of ["save", "target", "acknowledge"]) $(id).addEventListener("change", update);
$("cancel").onclick = () => fail("Cancelled. Choose the ZIP or folder again to restart.");
$("convert").onclick = async () => {
  if ($("convert").disabled) return;
  working = true;
  lock(true);
  update();
  try {
    if ($("save").value === "zip") {
      const handle = await window.showSaveFilePicker({ suggestedName: file.name.replace(/\.zip$/iu, "") + "-" + document.querySelector('input[name="target"]:checked').value + ".zip", types: [{ description: "ZIP archive", accept: { "application/zip": [".zip"] } }] });
      sink = await handle.createWritable();
    } else if ($("save").value === "disk") {
      const parent = await window.showDirectoryPicker({ mode: "readwrite" });
      const name = file.name.replace(/\.zip$/iu, "") + "-" + document.querySelector('input[name="target"]:checked').value;
      let exists = false;
      try { await parent.getDirectoryHandle(name); exists = true; }
      catch (error) { if (error.name !== "NotFoundError") throw error; }
      if (exists) throw new Error(`The folder ${name} already exists. Choose another destination or rename the existing folder.`);
      outputDirectory = await parent.getDirectoryHandle(name, { create: true });
    }
    $("status").hidden = false;
    $("cancel").hidden = false;
    $("error").hidden = true;
    worker.postMessage({ type: "convert", target: document.querySelector('input[name="target"]:checked').value, toIntel: $("intel").checked, mode: $("save").value });
  } catch (error) {
    if (error.name === "AbortError") { working = false; lock(false); update(); }
    else await fail(error.message);
  }
};
$("theme").onclick = () => {
  const dark = document.documentElement.dataset.theme ? document.documentElement.dataset.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
  document.documentElement.dataset.theme = dark ? "light" : "dark";
};
update();
lock(false);
if (supported) fetch("./release.json", { cache: "no-cache" }).then(response => { if (!response.ok) throw new Error(`Cannot load release information (${response.status})`); return response.json(); }).then(value => {
  if (!value.tag || !["windows", "linux"].every(target => Number.isSafeInteger(value.platforms?.[target]?.expandedBytes))) throw new Error("Invalid release information");
  release = value;
  update();
}).catch(error => fail(error.message));

if (!("webkitdirectory" in $("folder"))) {
  $("choose-folder").disabled = true;
  $("choose-folder").title = "Folder selection is unavailable in this browser. Choose a ZIP instead.";
}
