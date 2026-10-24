// Ekspor ABI + alamat deploy ke shared/ (package @printpitt/shared untuk backend dan frontend),
// lalu build package-nya, dan ABI ke ../indexer/abis bila repo indexer ada di sebelah (Envio).
// Jalankan dari root repo contracts setelah `forge build` dan (opsional) deploy:
//   node script/export.mjs
// Blok deploy dibaca dari receipt broadcast (broadcast/Deploy.s.sol/<chainId>/run-latest.json).
import { execSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const out = fileURLToPath(new URL('../shared/src/', import.meta.url));
const readJson = (p) => JSON.parse(readFileSync(p, 'utf8'));

const artifact = readJson(`${root}out/FotokopiKilat.sol/FotokopiKilat.json`);
const tidrx = readJson(`${root}out/TestIDRX.sol/TestIDRX.json`);

const deployments = {};
for (const f of readdirSync(`${root}deployments`).filter((f) => f.endsWith('.json'))) {
  const d = readJson(`${root}deployments/${f}`);
  const run = `${root}broadcast/Deploy.s.sol/${d.chainId}/run-latest.json`;
  let deployBlock = null;
  if (existsSync(run)) {
    const r = readJson(run);
    const tx = r.transactions.find((t) => t.transactionType === 'CREATE' && t.contractName === 'FotokopiKilat');
    const receipt = tx && r.receipts.find((x) => x.transactionHash === tx.hash);
    if (receipt && receipt.contractAddress?.toLowerCase() === d.fotokopiKilat.toLowerCase()) {
      deployBlock = Number(receipt.blockNumber);
    }
  }
  if (deployBlock === null) console.warn(`chain ${d.chainId}: receipt deploy tidak ditemukan, deployBlock = null`);
  deployments[d.chainId] = {
    address: d.fotokopiKilat,
    tidrx: d.tidrx,
    minter: d.minter,
    operator: d.operator,
    tokoA: d.tokoA,
    tokoB: d.tokoB,
    batasAntre: d.batasAntre,
    batasJemput: d.batasJemput ?? null,
    batasSengketa: d.batasSengketa ?? null,
    treasury: d.treasury ?? null,
    platformFeeBps: d.platformFeeBps ?? null,
    deployBlock,
  };
}

mkdirSync(out, { recursive: true });
const ts = `// DIBUAT OTOMATIS oleh script/export.mjs (repo PrintPitt/contracts). Jangan diedit manual.
export const fotokopiKilatAbi = ${JSON.stringify(artifact.abi, null, 2)} as const;

/** Token SIMULASI Rupiah (tIDRX, 2 desimal), bukan IDRX asli. */
export const tidrxAbi = ${JSON.stringify(tidrx.abi, null, 2)} as const;

export const deployments = ${JSON.stringify(deployments, null, 2)} as const;
`;
writeFileSync(`${out}fotokopiKilat.generated.ts`, ts);
// ABI untuk indexer Envio (indexer/config.yaml memakai abi_file_path); dilewati bila repo indexer tidak ada di sebelah.
const indexer = fileURLToPath(new URL('../../indexer/', import.meta.url));
if (existsSync(`${indexer}config.yaml`)) {
  mkdirSync(`${indexer}abis`, { recursive: true });
  writeFileSync(`${indexer}abis/FotokopiKilat.json`, JSON.stringify(artifact.abi, null, 2) + '\n');
  writeFileSync(`${indexer}abis/TestIDRX.json`, JSON.stringify(tidrx.abi, null, 2) + '\n');
  console.log(`ABI → ${indexer}abis`);
} else console.log('repo indexer tidak ditemukan di ../indexer, ABI indexer dilewati');

const shared = fileURLToPath(new URL('../shared/', import.meta.url));
if (existsSync(`${shared}node_modules`)) execSync('npm run build', { cwd: shared, stdio: 'inherit' });
else console.log('shared/node_modules belum ada: jalankan `npm --prefix shared install` lalu `npm --prefix shared run build`');
console.log(`ABI (${artifact.abi.length} + tIDRX ${tidrx.abi.length} item) + ${Object.keys(deployments).length} deployment → ${out}fotokopiKilat.generated.ts`);
for (const [chainId, d] of Object.entries(deployments)) console.log(`  chain ${chainId}: ${d.address}, tIDRX ${d.tidrx} (blok ${d.deployBlock})`);
