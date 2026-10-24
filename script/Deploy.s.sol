// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";
import {FotokopiKilat} from "../src/FotokopiKilat.sol";
import {TestIDRX} from "../src/TestIDRX.sol";

/// @notice Deploy token simulasi tIDRX + FotokopiKilat, katalog dalam Rupiah, fee relayer, 2 toko, buka sesi.
/// Alamat ditulis ke deployments/<chainId>.json. Blok deploy diambil dari receipt broadcast oleh `script/export.mjs`.
///
/// Env (semua opsional kecuali TOKO_A dan TOKO_B):
///   TOKO_A, TOKO_B         alamat toko
///   NAMA_TOKO_A/B          default "Toko A" / "Toko B"
///   MINTER                 alamat backend top-up yang boleh mencetak tIDRX (default: deployer saja)
///   RELAY_FEE              fee relayer dalam satuan tIDRX (2 desimal), default 10000 = Rp100
///   NFT_NAME, NFT_SYMBOL   default "Fotokopi Kilat" / "FKL" (nama project masih ditunda)
///   BATAS_ANTRE            detik, default 45
///   START_SESSION          default true
contract Deploy is Script {
    uint96 constant RP = 100; // 1 Rupiah = 100 satuan tIDRX

    function run() external returns (FotokopiKilat fk, TestIDRX idrx) {
        address tokoA = vm.envAddress("TOKO_A");
        address tokoB = vm.envAddress("TOKO_B");
        uint32 batasAntre = uint32(vm.envOr("BATAS_ANTRE", uint256(45)));
        address minter = vm.envOr("MINTER", address(0));

        vm.startBroadcast();
        idrx = new TestIDRX(msg.sender);
        if (minter != address(0)) idrx.grantRole(idrx.MINTER_ROLE(), minter);
        fk = new FotokopiKilat(
            vm.envOr("NFT_NAME", string("Fotokopi Kilat")), vm.envOr("NFT_SYMBOL", string("FKL")), batasAntre, idrx
        );
        fk.setKatalog(1, 5_000 * RP, 30, _resep(1, 0), "FOTOKOPI KTP");
        fk.setKatalog(2, 5_000 * RP, 30, _resep(2, 0), "BOARDING PASS");
        fk.setKatalog(3, 10_000 * RP, 45, _resep(1, 3), "LAMINATING IJAZAH");
        fk.setKatalog(4, 10_000 * RP, 45, _resep(2, 3), "MENU WARUNG");
        fk.setFeeRelay(uint96(vm.envOr("RELAY_FEE", uint256(100 * RP))));
        fk.registerShop(tokoA, vm.envOr("NAMA_TOKO_A", string("Toko A")));
        fk.registerShop(tokoB, vm.envOr("NAMA_TOKO_B", string("Toko B")));
        if (vm.envOr("START_SESSION", true)) fk.startSession();
        vm.stopBroadcast();

        string memory key = "deploy";
        vm.serializeAddress(key, "fotokopiKilat", address(fk));
        vm.serializeAddress(key, "tidrx", address(idrx));
        vm.serializeAddress(key, "operator", fk.operator());
        vm.serializeAddress(key, "minter", minter == address(0) ? fk.operator() : minter);
        vm.serializeAddress(key, "tokoA", tokoA);
        vm.serializeAddress(key, "tokoB", tokoB);
        vm.serializeUint(key, "batasAntre", batasAntre);
        string memory json = vm.serializeUint(key, "chainId", block.chainid);
        string memory path = string.concat(vm.projectRoot(), "/deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
        console.log("TestIDRX (simulasi):", address(idrx));
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
