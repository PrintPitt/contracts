# PrintPitt · contracts

Contract `FotokopiKilat` (order escrow, rebutan claim, payout turun per detik, refund, NFT struk) dan token simulasi
Rupiah `TestIDRX` (tIDRX, 2 desimal, `permit`) untuk Monad testnet. Foundry 1.8.6, solc 0.8.31, OpenZeppelin 5.7.0.
Dokumentasi: repo `PrintPitt/vault` → `04-Architecture/Desain Contract.md`.

## Struktur

| Folder | Isi |
|---|---|
| `src/` | `FotokopiKilat.sol`, `TestIDRX.sol` |
| `test/` | unit test + invariant |
| `script/` | `Deploy.s.sol`, `export.mjs` (ABI + alamat → `shared/`, ABI → `../indexer/abis`) |
| `shared/` | package `@printpitt/shared`: ABI, alamat deploy, helper (`teksValid`, `hitungPayout`, `formatRupiah`, tipe EIP-712, `GAS_LIMIT`) |
| `deployments/` | alamat per chain (ditulis script deploy) |

## Mulai

```bash
git clone --recurse-submodules https://github.com/PrintPitt/contracts.git
forge build
forge test                       # invariant penuh: FOUNDRY_PROFILE=deep (CPU berat)
npm --prefix shared install
```

## Deploy (Monad testnet, chain 10143)

Private key tidak pernah ditulis ke file: pakai keystore Foundry.

```bash
cast wallet new ~/.foundry/keystores deployer
TOKO_A=0x… TOKO_B=0x… MINTER=0x… forge script script/Deploy.s.sol \
  --rpc-url $MONAD_RPC_URL --account deployer --broadcast
node script/export.mjs           # tulis shared/src/*.generated.ts, build shared, salin ABI ke ../indexer/abis
```

Env opsional: `NAMA_TOKO_A`, `NAMA_TOKO_B`, `RELAY_FEE` (default 10000 = Rp100), `NFT_NAME`, `NFT_SYMBOL`,
`BATAS_ANTRE` (45), `START_SESSION` (true).

## Memakai `@printpitt/shared`

Selama repo private, backend dan frontend memasang package ini sebagai tarball (`npm run pack:vendor` di `shared/`,
atau `scripts/sync-shared.sh` di repo backend). Setelah repo publik bisa langsung dari git.
