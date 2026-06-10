
const fs = require("fs");
const path = require("path");

const filePath = "frontend/src/App.jsx";

if (!fs.existsSync(filePath)) {
  console.log("❌ App.jsx non trovato");
  process.exit(1);
}

console.log("✅ Trovato App.jsx");

// backup
const backup = filePath.replace(".jsx", "_backup_manual_fix.jsx");
if (!fs.existsSync(backup)) {
  fs.copyFileSync(filePath, backup);
  console.log("✅ Backup creato");
}

let content = fs.readFileSync(filePath, "utf8");

// ✅ FIX ROUTING TAB ROTTO
content = content.replace(
  /\{tab === \"notifiedDeadlines[^\n]*\n/g,
  '{tab === "notifiedDeadlines" && renderDeadlineArchivePage()}\n'
);

content = content.replace(
  /\{tab === \"messageManager[^\n]*\n/g,
  '{tab === "messageManager" && renderMessageManagerPage()}\n'
);

// ✅ BLOCCO FINALE COMPLETO
content = content.replace(
  /\{tab !== \"dashboard\"[^\n]*renderEntityPage\(tab\)\}/,
  `{tab !== "dashboard" &&
 tab !== "backup" &&
 tab !== "customerHistory" &&
 tab !== "notifiedDeadlines" &&
 tab !== "messageManager" &&
 renderEntityPage(tab)}`
);

// ✅ FIX && HTML
content = content.replace(/&amp;&amp;/g, "&&");

// ✅ FIX style bug
content = content.replace(
  /flexDirection:\s*"column"\s*4/g,
  `flexDirection: "column",\n  gap: 4`
);

// ✅ RIMUOVE } EXTRA PRIMA DEGLI STILI
const marker = "\nconst appRootStyle = {";
const i = content.indexOf(marker);
if (i !== -1) {
  let before = content.slice(0, i);
  before = before.replace(/\n\s*\}\s*\n\s*\}\s*$/, "\n}\n");
  content = before + content.slice(i);
}

fs.writeFileSync(filePath, content, "utf8");

console.log("✅ FIX COMPLETATO");
console.log("👉 Ora fai: npm run dev");
