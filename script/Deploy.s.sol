// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";
import {FotokopiKilat} from "../src/FotokopiKilat.sol";
import {TestIDRX} from "../src/TestIDRX.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Deploy token simulasi tIDRX + FotokopiKilat v2, katalog Rupiah (tetap + per halaman), fee relayer, 2 toko, buka sesi.
/// Alamat ditulis ke deployments/<chainId>.json. Blok deploy diambil dari receipt broadcast oleh `script/export.mjs`.
///
/// Env (semua opsional):
///   TOKEN                  token pembayaran yang sudah ada (mainnet: IDRX 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22,
///                          2 desimal). Kosong = deploy TestIDRX (simulasi) + MINTER
///   TOKO_A, TOKO_B         alamat toko demo yang didaftarkan operator (kosong = tidak ada; toko bisa daftar sendiri)
///   NAMA_TOKO_A/B          default "Toko A" / "Toko B"
///   MINTER                 alamat backend top-up yang boleh mencetak tIDRX (default: deployer saja)
///   RELAY_FEE              fee layanan relayer dalam satuan tIDRX (2 desimal), default 20000 = Rp200
///   TREASURY               penerima fee platform + langganan Toko Pro (default: deployer)
///   PLATFORM_FEE_BPS       potongan platform dari payout toko, default 300 = 3%
///   HARGA_PRO              harga Toko Pro per 30 hari dalam satuan tIDRX, default 5000000 = Rp50.000
///   NFT_NAME, NFT_SYMBOL   default "Fotokopi Kilat" / "FKL" (nama project masih ditunda)
///   BATAS_ANTRE            detik, default 45
///   BATAS_JEMPUT           detik setelah Siap sebelum order bisa ditutup tanpa serah terima, default 600
///   BATAS_SENGKETA         detik setelah batas jemput sebelum sengketa bisa ditutup otomatis (50/50), default 86400
///   START_SESSION          default true
contract Deploy is Script {
    uint96 constant RP = 100; // 1 Rupiah = 100 satuan tIDRX

    function run() external returns (FotokopiKilat fk, IERC20 token) {
        address tokoA = vm.envOr("TOKO_A", address(0));
        address tokoB = vm.envOr("TOKO_B", address(0));
        address tokenAda = vm.envOr("TOKEN", address(0));
        uint32 batasAntre = uint32(vm.envOr("BATAS_ANTRE", uint256(45)));
        uint32 batasJemput = uint32(vm.envOr("BATAS_JEMPUT", uint256(600)));
        uint32 batasSengketa = uint32(vm.envOr("BATAS_SENGKETA", uint256(1 days)));
        address minter = vm.envOr("MINTER", address(0));

        vm.startBroadcast();
        if (tokenAda == address(0)) {
            TestIDRX idrx = new TestIDRX(msg.sender);
            if (minter != address(0)) idrx.grantRole(idrx.MINTER_ROLE(), minter);
            token = idrx;
        } else {
            token = IERC20(tokenAda);
        }
        fk = new FotokopiKilat(
            vm.envOr("NFT_NAME", string("Fotokopi Kilat")),
            vm.envOr("NFT_SYMBOL", string("FKL")),
            batasAntre,
            batasJemput,
            batasSengketa,
            token
        );
        // Harga tetap (mode demo mini-game, 1 halaman)
        fk.setKatalog(1, 5_000 * RP, 0, 30, 0, _resep(1, 0), "FOTOKOPI KTP");
        fk.setKatalog(2, 5_000 * RP, 0, 30, 0, _resep(2, 0), "BOARDING PASS");
        fk.setKatalog(3, 10_000 * RP, 0, 45, 0, _resep(1, 3), "LAMINATING IJAZAH");
        fk.setKatalog(4, 10_000 * RP, 0, 45, 0, _resep(2, 3), "MENU WARUNG");
        // Harga per halaman (order dokumen nyata): dasar + per halaman, batas kerja dasar + per halaman
        fk.setKatalog(5, 1_000 * RP, 500 * RP, 20, 3, _resep(2, 0), "PRINT DOKUMEN");
        fk.setKatalog(6, 500 * RP, 300 * RP, 20, 2, _resep(1, 0), "FOTOKOPI DOKUMEN");
        fk.setKatalog(7, 3_000 * RP, 1_000 * RP, 30, 5, _resep(2, 3), "PRINT + LAMINATING");
        fk.setFeeRelay(uint96(vm.envOr("RELAY_FEE", uint256(200 * RP))));
        address treasury = vm.envOr("TREASURY", msg.sender);
        fk.setPlatform(
            uint16(vm.envOr("PLATFORM_FEE_BPS", uint256(300))), treasury, uint96(vm.envOr("HARGA_PRO", uint256(50_000 * RP)))
        );
        if (tokoA != address(0)) fk.registerShop(tokoA, vm.envOr("NAMA_TOKO_A", string("Toko A")));
        if (tokoB != address(0)) fk.registerShop(tokoB, vm.envOr("NAMA_TOKO_B", string("Toko B")));
        if (vm.envOr("START_SESSION", true)) fk.startSession();
        vm.stopBroadcast();

        string memory key = "deploy";
        vm.serializeAddress(key, "fotokopiKilat", address(fk));
        vm.serializeAddress(key, "tidrx", address(token)); // nama field lama; berisi token pembayaran (tIDRX atau IDRX)
        vm.serializeAddress(key, "operator", fk.operator());
        vm.serializeAddress(key, "minter", tokenAda != address(0) ? address(0) : minter == address(0) ? fk.operator() : minter);
        vm.serializeAddress(key, "tokoA", tokoA);
        vm.serializeAddress(key, "tokoB", tokoB);
        vm.serializeUint(key, "batasAntre", batasAntre);
        vm.serializeUint(key, "batasJemput", batasJemput);
        vm.serializeUint(key, "batasSengketa", batasSengketa);
        vm.serializeAddress(key, "treasury", fk.treasury());
        vm.serializeUint(key, "platformFeeBps", fk.platformFeeBps());
        string memory json = vm.serializeUint(key, "chainId", block.chainid);
        string memory path = string.concat(vm.projectRoot(), "/deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
        console.log(tokenAda == address(0) ? "TestIDRX (simulasi):" : "Token pembayaran:", address(token));
        console.log("FotokopiKilat:", address(fk));
        console.log("ditulis ke:", path);
    }

    /// @dev b = 0 berarti resep satu langkah.
    function _resep(uint8 a, uint8 b) internal pure returns (uint8[] memory r) {
        r = new uint8[](b == 0 ? 1 : 2);
        r[0] = a;
        if (b != 0) r[1] = b;
    }
}
