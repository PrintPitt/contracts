// Konstanta dan helper bersama untuk frontend dan backend (package @printpitt/shared).
// Aturan di sini meniru contract FotokopiKilat; contract tetap sumber kebenaran.
import { deployments, fotokopiKilatAbi, tidrxAbi } from './fotokopiKilat.generated.ts';

export { deployments, fotokopiKilatAbi, tidrxAbi };

/** Kode langkah mini-game, sama dengan contract (1..3). */
export const LANGKAH = { FOTOKOPI: 1, PRINT: 2, LAMINATING: 3 } as const;
export type KodeLangkah = (typeof LANGKAH)[keyof typeof LANGKAH];

/** Status order, urutan sama dengan enum `Status` di contract. */
export const STATUS = ['None', 'Open', 'Claimed', 'Finished', 'Expired'] as const;

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

/** Domain EIP-712: contract memakai EIP712("FotokopiKilat", "1"); tIDRX memakai nama token + versi "1". */
export const domainPesanan = (chainId: number, verifyingContract: `0x${string}`) =>
  ({ name: 'FotokopiKilat', version: '1', chainId, verifyingContract }) as const;
export const domainTidrx = (chainId: number, verifyingContract: `0x${string}`) =>
  ({ name: 'Test IDRX (simulasi)', version: '1', chainId, verifyingContract }) as const;

/**
 * Gas limit per fungsi. Monad menagih gas LIMIT, bukan gas terpakai, jadi jangan pakai estimasi + buffer besar.
 * Angka = maks. terukur di EVM lokal (forge --gas-report) + ~30%. WAJIB diukur ulang di testnet (BLZ-07.T4).
 */
export const GAS_LIMIT = {
  createOrder: 300_000n,
  createOrderFor: 370_000n,
  approve: 60_000n,
  mint: 95_000n,
  claim: 60_000n,
  completeStep: 180_000n,
  expire: 70_000n,
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
