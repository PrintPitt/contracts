// Shared constants and helpers for frontend and backend (package @printpitt/shared).
// The rules here mirror the FotokopiKilat contract; the contract stays the source of truth.
import { deployments, fotokopiKilatAbi, tidrxAbi } from './fotokopiKilat.generated.ts';

export { deployments, fotokopiKilatAbi, tidrxAbi };

/** Step codes (copy, print, laminate), same as the contract (1..3). */
export const LANGKAH = { FOTOKOPI: 1, PRINT: 2, LAMINATING: 3 } as const;
export type KodeLangkah = (typeof LANGKAH)[keyof typeof LANGKAH];

/** Order status, same order as the contract's `Status` enum (v2). Siap = Ready, Sengketa = Disputed, Diputuskan = Resolved. */
export const STATUS = ['None', 'Open', 'Claimed', 'Siap', 'Finished', 'Expired', 'Sengketa', 'Diputuskan'] as const;
/** Final statuses: funds are settled, no further actions. */
export const STATUS_FINAL = ['Finished', 'Expired', 'Diputuskan'] as const;
export const MAX_HALAMAN = 500;
export const NOL32 = `0x${'0'.repeat(64)}` as const;

export const MAX_TEXT = 40;

/** tIDRX (simulated IDRX) uses 2 decimals like real IDRX: Rp1 = 100 units. */
export const DESIMAL_RUPIAH = 2;
export const rupiahKeSatuan = (rp: number) => BigInt(Math.round(rp * 100));
export const satuanKeRupiah = (v: bigint) => Number(v) / 100;
/** "Rp5.000" (no decimals when whole; Indonesian number format). */
export function formatRupiah(v: bigint) {
  return 'Rp' + satuanKeRupiah(v).toLocaleString('id-ID', { minimumFractionDigits: 0, maximumFractionDigits: 2 });
}

/** EIP-712 types for `createOrderFor`, same as PESANAN_TYPEHASH in the contract. */
export const PESANAN_TYPES = {
  Pesanan: [
    { name: 'pelanggan', type: 'address' },
    { name: 'jenis', type: 'uint8' },
    { name: 'teks', type: 'string' },
    { name: 'halaman', type: 'uint16' },
    { name: 'dokumen', type: 'bytes32' },
    { name: 'kodeHash', type: 'bytes32' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
    { name: 'maxFee', type: 'uint256' },
  ],
} as const;

/** EIP-2612 `permit` types of tIDRX. */
export const PERMIT_TYPES = {
  Permit: [
    { name: 'owner', type: 'address' },
    { name: 'spender', type: 'address' },
    { name: 'value', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
  ],
} as const;

/** EIP-712 domains: the contract uses EIP712("FotokopiKilat", "2"); tIDRX uses the token name + version "1". */
export const domainPesanan = (chainId: number, verifyingContract: `0x${string}`) =>
  ({ name: 'FotokopiKilat', version: '2', chainId, verifyingContract }) as const;
export const domainTidrx = (chainId: number, verifyingContract: `0x${string}`) =>
  ({ name: 'Test IDRX (simulasi)', version: '1', chainId, verifyingContract }) as const;

/**
 * Gas limit per function. Monad charges the gas LIMIT (receipt `gasUsed` = limit), so a big buffer costs more.
 * Real needs from `eth_estimateGas` on Monad testnet 2026-10-24 (worst case):
 *   createOrderFor + permit + teks 40 byte 378.901 · createOrder teks 3 byte 204.453 (40-byte text ±+66k)
 *   completeStep last step (payout + NFT) 208,134 · expire 71,781 · mint to a new address 72,550
 *   claim 55.530 · approve 52.937
 * Limit = worst case + ~12–15%. v2 (testnet, contract 0xA2a5…88aa): createOrderFor + permit + teks 40 byte +
 * dokumen + kode 418.596 (mode demo 317.077), completeStep → Siap 52.052, serahkan 194.225, claim 55.559.
 */
export const GAS_LIMIT = {
  createOrder: 350_000n,
  createOrderFor: 470_000n,
  approve: 62_000n,
  mint: 100_000n, // first mint on a fresh token (totalSupply 0) 89,618; afterwards ±72,550
  claim: 65_000n,
  completeStep: 240_000n, // last step without a handover code = full settlement + fee + NFT (v2.2: 199,003)
  expire: 85_000n,
  // full settlement = payout + treasury fee + refund + NFT mint (serahkan measured on v2.1: 236,005)
  expireSiap: 260_000n,
  serahkan: 260_000n,
  komplain: 40_000n, // v2.2: 34.777
  putuskan: 140_000n, // v2.2: 123.734
  tutupSengketa: 140_000n, // same as putuskan
  langgananPro: 135_000n, // v2.2: 117.060
} as const;

/** Text validation exactly like `_teksValid` in the contract: 1..40 printable ASCII bytes, no < > & " ' \ */
export function teksValid(s: string): boolean {
  if (s.length === 0 || s.length > MAX_TEXT) return false;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x20 || c > 0x7e) return false;
    if ('<>&"\'\\'.includes(s[i])) return false;
  }
  return true;
}

/** Price and work limit for `halaman` pages; same as `hargaUntuk` in the contract. */
export function hitungHarga(
  k: { hargaDasar: bigint; hargaPerHalaman: bigint; batasDasar: number; batasPerHalaman: number },
  halaman: number,
) {
  return { harga: k.hargaDasar + k.hargaPerHalaman * BigInt(halaman), batasKerja: k.batasDasar + k.batasPerHalaman * halaman };
}

/** Payout when finished after `kerja` seconds; same as `_payout` (rounded down). */
export function hitungPayout(harga: bigint, batasKerja: number, kerja: number): bigint {
  if (kerja >= batasKerja) return 0n;
  return (harga * BigInt(batasKerja - kerja)) / BigInt(batasKerja);
}

/** Get the deployment for a chain, or throw a clear error. */
export function deploymentUntuk(chainId: number | string) {
  const d = (deployments as Record<string, (typeof deployments)[keyof typeof deployments]>)[String(chainId)];
  if (!d) throw new Error(`No deployment for chain ${chainId} yet. Run the deploy, then node script/export.mjs`);
  return d;
}

// ---------------------------------------------------------------- backend v2 (documents + location)

/** EIP-191 (personal_sign) message signed to download an order's document. `waktu` = Date.now() ms, valid for 5 minutes. The message text itself must not change (the backend verifies it). */
export const pesanUnduh = (dokumen: string, orderId: bigint | number, waktu: number) =>
  `PrintPitt: unduh dokumen ${dokumen.toLowerCase()} order #${orderId} pada ${waktu}`;
/** Message a shop signs to register / update its location. */
export const pesanLokasiToko = (toko: string, lat: number, lng: number, waktu: number) =>
  `PrintPitt: lokasi toko ${toko.toLowerCase()} ${lat},${lng} pada ${waktu}`;
/** Message a customer signs to attach a (coarse) location to an order. */
export const pesanLokasiOrder = (orderId: bigint | number, lat: number, lng: number, waktu: number) =>
  `PrintPitt: lokasi order #${orderId} ${lat},${lng} pada ${waktu}`;

/** Coordinates are rounded to 3 decimals (±110 m) before sending/storing, so precise locations are never stored. */
export const bulatkanKoordinat = (x: number) => Math.round(x * 1000) / 1000;

/** Distance between two points (km), haversine formula. */
export function jarakKm(a: { lat: number; lng: number }, b: { lat: number; lng: number }) {
  const r = (d: number) => (d * Math.PI) / 180;
  const h = Math.sin(r(b.lat - a.lat) / 2) ** 2 + Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.sin(r(b.lng - a.lng) / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(h));
}
