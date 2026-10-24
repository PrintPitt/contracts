# PrintPitt · contracts

`FotokopiKilat` (order escrow, shop claim race, payout that drops every second, refund, NFT receipt) and `TestIDRX`, a simulated Rupiah token (tIDRX, 2 decimals, `permit`) for Monad testnet. Foundry 1.8.6, solc 0.8.31, OpenZeppelin 5.7.0.
Design docs: repo `PrintPitt/vault` → `04-Architecture/Desain Contract.md`.

> Contract, function, event and storage names are in Indonesian (`pesanan` = order, `toko` = shop, `langkah` = step, `siap` = ready, `serahkan` = hand over, `sengketa` = dispute, `batas` = limit). They are part of the deployed, verified ABI and are kept as is.

## Deployments

| Network | Contract | Address |
|---|---|---|
| Monad testnet (10143) | `FotokopiKilat` | see [`deployments/10143.json`](deployments/10143.json) |
| Monad testnet (10143) | `TestIDRX` | see [`deployments/10143.json`](deployments/10143.json) |
| Monad mainnet (143) | `FotokopiKilat` (paid in real IDRX) | see [`deployments/143.json`](deployments/143.json) |

All deployed contracts are verified on Sourcify (`exact_match`).

## Layout

| Folder | Contents |
|---|---|
| `src/` | `FotokopiKilat.sol`, `TestIDRX.sol` |
| `test/` | unit tests + invariants |
| `script/` | `Deploy.s.sol`, `export.mjs` (ABI + addresses → `shared/`, ABI → `../indexer/abis`) |
| `shared/` | package `@printpitt/shared`: ABI, deployed addresses, helpers (`teksValid`, `hitungPayout`, `formatRupiah`, EIP-712 types, `GAS_LIMIT`) |
| `deployments/` | addresses per chain (written by the deploy script) |

## Get started

```bash
git clone --recurse-submodules https://github.com/PrintPitt/contracts.git
forge build
forge test                       # full invariants: FOUNDRY_PROFILE=deep (CPU heavy)
npm --prefix shared install
```

## Deploy (Monad testnet, chain 10143)

Private keys are never written to a file: use a Foundry keystore.

```bash
cast wallet new ~/.foundry/keystores deployer
TOKO_A=0x… TOKO_B=0x… MINTER=0x… forge script script/Deploy.s.sol \
  --rpc-url $MONAD_RPC_URL --account deployer --broadcast
node script/export.mjs           # writes shared/src/*.generated.ts, builds shared, copies the ABI to ../indexer/abis
```

Optional env: `TOKEN` (existing payment token, e.g. IDRX on mainnet), `NAMA_TOKO_A`, `NAMA_TOKO_B`, `RELAY_FEE` (default 20000 = Rp200), `PLATFORM_FEE_BPS` (300 = 3%), `HARGA_PRO` (Shop Pro, default Rp50,000 / 30 days), `NFT_NAME`, `NFT_SYMBOL`, `BATAS_ANTRE` (queue limit, 45 s), `BATAS_JEMPUT` (pickup window, 600 s), `BATAS_SENGKETA` (dispute window, 86400 s), `HARGA_BAGI`, `START_SESSION` (true). Full list in the header of `script/Deploy.s.sol`.

## Using `@printpitt/shared`

While the repos are private, backend and frontend install this package as a tarball (`npm run pack:vendor` in `shared/`, or `scripts/sync-shared.sh` in the backend repo). Once the repos are public it can be installed straight from git.
