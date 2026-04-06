#!/usr/bin/env node

const { execSync } = require("child_process");
const https = require("https");
const http = require("http");
const fs = require("fs");
const path = require("path");
const os = require("os");

const APP_NAME = "ClaudeTakip";
const DMG_URL =
  "https://github.com/BatuhanAkpunar/ClaudeTakip/releases/latest/download/ClaudeTakip.dmg";
const INSTALL_DIR = "/Applications";
const APP_PATH = path.join(INSTALL_DIR, `${APP_NAME}.app`);

function log(msg) {
  console.log(`\x1b[36m${APP_NAME}\x1b[0m ${msg}`);
}

function error(msg) {
  console.error(`\x1b[31m${APP_NAME}\x1b[0m ${msg}`);
  process.exit(1);
}

if (process.platform !== "darwin") {
  error("ClaudeTakip is only available for macOS.");
}

if (fs.existsSync(APP_PATH)) {
  log(`Already installed at ${APP_PATH}`);
  log("Launching...");
  execSync(`open "${APP_PATH}"`);
  process.exit(0);
}

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "claudetakip-"));
const dmgPath = path.join(tmpDir, `${APP_NAME}.dmg`);

function cleanup() {
  try {
    execSync(`hdiutil detach "/Volumes/${APP_NAME}" -quiet 2>/dev/null`, {
      stdio: "ignore",
    });
  } catch {}
  try {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  } catch {}
}

process.on("SIGINT", () => {
  cleanup();
  process.exit(1);
});

function download(url) {
  return new Promise((resolve, reject) => {
    const get = url.startsWith("https") ? https.get : http.get;
    const follow = (u) => {
      const getter = u.startsWith("https") ? https.get : http.get;
      getter(u, { headers: { "User-Agent": "claudetakip-installer" } }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          follow(res.headers.location);
          return;
        }
        if (res.statusCode !== 200) {
          reject(new Error(`Download failed (HTTP ${res.statusCode})`));
          return;
        }
        const total = parseInt(res.headers["content-length"], 10) || 0;
        let downloaded = 0;
        const file = fs.createWriteStream(dmgPath);
        res.pipe(file);
        res.on("data", (chunk) => {
          downloaded += chunk.length;
          if (total > 0) {
            const pct = Math.round((downloaded / total) * 100);
            process.stdout.write(
              `\r\x1b[36m${APP_NAME}\x1b[0m Downloading... ${pct}%`
            );
          }
        });
        file.on("finish", () => {
          process.stdout.write("\n");
          resolve();
        });
        file.on("error", reject);
        res.on("error", reject);
      }).on("error", reject);
    };
    follow(url);
  });
}

async function main() {
  log("Downloading latest release...");
  await download(DMG_URL);

  log("Mounting disk image...");
  const mountOutput = execSync(
    `hdiutil attach "${dmgPath}" -nobrowse`
  ).toString();
  const volumeLine = mountOutput
    .split("\n")
    .find((l) => l.includes("/Volumes/"));
  const volumePath = volumeLine
    ? volumeLine.split("\t").pop().trim()
    : `/Volumes/${APP_NAME}`;

  const appSrc = path.join(volumePath, `${APP_NAME}.app`);
  if (!fs.existsSync(appSrc)) {
    cleanup();
    error(`${APP_NAME}.app not found in disk image.`);
  }

  log(`Installing to ${INSTALL_DIR}...`);
  try {
    execSync(`cp -R "${appSrc}" "${INSTALL_DIR}/"`);
  } catch {
    log("Permission denied. Retrying with sudo...");
    execSync(`sudo cp -R "${appSrc}" "${INSTALL_DIR}/"`);
  }

  cleanup();

  log("Installed successfully!");
  log("Launching...");
  execSync(`open "${APP_PATH}"`);
}

main().catch((err) => {
  cleanup();
  error(err.message);
});
