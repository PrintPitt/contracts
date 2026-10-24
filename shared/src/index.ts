// Konstanta dan helper bersama untuk frontend dan backend (package @printpitt/shared).
// Aturan di sini meniru contract FotokopiKilat; contract tetap sumber kebenaran.
import { deployments, fotokopiKilatAbi, tidrxAbi } from './fotokopiKilat.generated.ts';

export { deployments, fotokopiKilatAbi, tidrxAbi };

/** Kode langkah mini-game, sama dengan contract (1..3). */
export const LANGKAH = { FOTOKOPI: 1, PRINT: 2, LAMINATING: 3 } as const;
export type KodeLangkah = (typeof LANGKAH)[keyof typeof LANGKAH];

/** Status order, urutan sama dengan enum `Status` di contract (v2). */
export const STATUS = ['None', 'Open', 'Claimed', 'Siap', 'Finished', 'Expired', 'Sengketa', 'Diputuskan'] as const;
/** Status final: dana sudah dibagi, tidak ada aksi lagi. */
export const STATUS_FINAL = ['Finished', 'Expired', 'Diputuskan'] as const;
export const MAX_HALAMAN = 500;
export const NOL32 = `0x${'0'.repeat(64)}` as const;

export const MAX_TEXT = 40;

/** tIDRX (simulasi IDRX) memakai 2 desimal seperti IDRX asli: Rp1 = 100 satuan. */
export const DESIMAL_RUPIAH = 2;
export const rupiahKeSatuan = (rp: number) => BigInt(Math.round(rp * 100));
export const satuanKeRupiah = (v: bigint) => Number(v) / 100;
/** "Rp5.000" (tanpa desimal bila bulat). */
export function formatRupiah(v: bigint) {
  return 'Rp' + satuanKeRupiah(v).toLocaleString('id-ID', { minimumFractionDigits: 0, maximumFractionDigits: 2 });
}

/** Tipe EIP-712 untuk `createOrderFor`, sama dengan PESANAN_TYPEHASH di contract. */
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

/** Tipe EIP-2612 `permit` milik tIDRX. */
export const PERMIT_TYPES = {
  Permit: [
    { name: 'owner', type: 'address' },
    { name: 'spender', type: 'address' },
    { name: 'value', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
  ],
} as const;

/** Domain EIP-712: contract memakai EIP712("FotokopiKilat", "2"); tIDRX memakai nama token + versi "1". */
export const domainPesanan = (chainId: number, verifyingContract: `0x${string}`) =>
  ({ name: 'FotokopiKilat', version: '2', chainId, verifyingContract }) as const;
export const domainTidrx = (chainId: number, verifyingContract: `0x${string}`) =>
  ({ name: 'Test IDRX (simulasi)', version: '1', chainId, verifyingContract }) as const;

/**
 * Gas limit per fungsi. Monad menagih gas LIMIT (receipt `gasUsed` = limit), jadi buffer besar = bayar lebih mahal.
 * Kebutuhan asli dari `eth_estimateGas` di Monad testnet 2026-10-24 (kasus terberat):
 *   createOrderFor + permit + teks 40 byte 378.901 · createOrder teks 3 byte 204.453 (teks 40 byte ±+66k)
 *   completeStep langkah terakhir (payout + NFT) 208.134 · expire 71.781 · mint ke alamat baru 72.550
 *   claim 55.530 · approve 52.937
 * Limit = kebutuhan terberat + ~12–15%. v2 (testnet, contract 0xA2a5…88aa): createOrderFor + permit + teks 40 byte +
 * dokumen + kode 418.596 (mode demo 317.077), completeStep → Siap 52.052, serahkan 194.225, claim 55.559.
 */
export const GAS_LIMIT = {
  createOrder: 350_000n,
  createOrderFor: 470_000n,
  approve: 62_000n,
  mint: 100_000n, // mint pertama di token baru (totalSupply 0) 89.618; berikutnya ±72.550
  claim: 65_000n,
  completeStep: 260_000n,
  expire: 85_000n,
  // v2: penyelesaian penuh = payout + refund + mint NFT (serahkan terukur 194.225)
  expireSiap: 220_000n,
  serahkan: 220_000n,
  komplain: 70_000n, // belum terukur
  putuskan: 170_000n, // belum terukur
} as const;

/** Validasi teks persis seperti `_teksValid` di contract: 1..40 byte ASCII cetak, tanpa < > & " ' \ */
export function teksValid(s: string): boolean {
  if (s.length === 0 || s.length > MAX_TEXT) return false;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x20 || c > 0x7e) return false;
    if ('<>&"\'\\'.includes(s[i])) return false;
  }
  return true;
}

/** Harga dan batas kerja untuk `halaman` halaman; sama dengan `hargaUntuk` di contract. */
export function hitungHarga(
  k: { hargaDasar: bigint; hargaPerHalaman: bigint; batasDasar: number; batasPerHalaman: number },
  halaman: number,
) {
  return { harga: k.hargaDasar + k.hargaPerHalaman * BigInt(halaman), batasKerja: k.batasDasar + k.batasPerHalaman * halaman };
}

/** Payout bila selesai setelah `kerja` detik; sama dengan `_payout` (pembulatan ke bawah). */
export function hitungPayout(harga: bigint, batasKerja: number, kerja: number): bigint {
  if (kerja >= batasKerja) return 0n;
  return (harga * BigInt(batasKerja - kerja)) / BigInt(batasKerja);
}

/** Ambil deployment untuk chain tertentu, atau lempar error yang jelas. */
export function deploymentUntuk(chainId: number | string) {
  const d = (deployments as Record<string, (typeof deployments)[keyof typeof deployments]>)[String(chainId)];
  if (!d) throw new Error(`Belum ada deployment untuk chain ${chainId}. Jalankan deploy lalu node script/export.mjs`);
  return d;
}
