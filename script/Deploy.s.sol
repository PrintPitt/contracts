// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Script, console} from "forge-std/Script.sol";
import {FotokopiKilat} from "../src/FotokopiKilat.sol";
import {TestIDRX} from "../src/TestIDRX.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Deploys the simulated tIDRX token + FotokopiKilat v2, the Rupiah catalog (fixed + per page), the relayer fee, 2 shops, and opens a session.
/// Addresses are written to deployments/<chainId>.json. The deploy block is read from the broadcast receipt by `script/export.mjs`.
///
/// Env (all optional):
///   TOKEN                  existing payment token (mainnet: IDRX 0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22,
///                          2 decimals). Empty = deploy TestIDRX (simulation) + MINTER
///   TOKO_A, TOKO_B         demo shop addresses registered by the operator (empty = none; shops can register themselves)
///   NAMA_TOKO_A/B          default "Toko A" / "Toko B"
///   MINTER                 top-up backend address allowed to mint tIDRX (default: deployer only)
///   RELAY_FEE              relayer service fee in tIDRX units (2 decimals), default 20000 = Rp200
///   TREASURY               receives the platform fee + Shop Pro subscriptions (default: deployer)
///   PLATFORM_FEE_BPS       platform cut of the shop payout, default 300 = 3%
///   HARGA_PRO              Shop Pro price per 30 days in tIDRX units, default 5000000 = Rp50,000
///   NFT_NAME, NFT_SYMBOL   default "Fotokopi Kilat" / "FKL" (working name)
///   BATAS_ANTRE            queue limit in seconds, default 45
///   BATAS_JEMPUT           seconds after Ready before an order can be closed without handover, default 600
///   BATAS_SENGKETA         seconds after the pickup limit before a dispute can be closed automatically (50/50), default 86400
///   HARGA_BAGI             all catalog prices are divided by this (cheap mainnet demo: 10 → ID copy Rp500), default 1
///   START_SESSION          default true
contract Deploy is Script {
    uint96 constant RP = 100; // 1 Rupiah = 100 tIDRX units

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
        uint96 b = uint96(vm.envOr("HARGA_BAGI", uint256(1)));
        // Fixed prices (mini-game demo mode, 1 page)
        fk.setKatalog(1, 5_000 * RP / b, 0, 30, 0, _resep(1, 0), "FOTOKOPI KTP");
        fk.setKatalog(2, 5_000 * RP / b, 0, 30, 0, _resep(2, 0), "BOARDING PASS");
        fk.setKatalog(3, 10_000 * RP / b, 0, 45, 0, _resep(1, 3), "LAMINATING IJAZAH");
        fk.setKatalog(4, 10_000 * RP / b, 0, 45, 0, _resep(2, 3), "MENU WARUNG");
        // Per-page prices (real document orders): base + per page, work limit base + per page
        fk.setKatalog(5, 1_000 * RP / b, 500 * RP / b, 20, 3, _resep(2, 0), "PRINT DOKUMEN");
        fk.setKatalog(6, 500 * RP / b, 300 * RP / b, 20, 2, _resep(1, 0), "FOTOKOPI DOKUMEN");
        fk.setKatalog(7, 3_000 * RP / b, 1_000 * RP / b, 30, 5, _resep(2, 3), "PRINT + LAMINATING");
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
        vm.serializeAddress(key, "tidrx", address(token)); // legacy field name; holds the payment token (tIDRX or IDRX)
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
        console.log(tokenAda == address(0) ? "TestIDRX (simulation):" : "Payment token:", address(token));
        console.log("FotokopiKilat:", address(fk));
        console.log("written to:", path);
    }

    /// @dev b = 0 means a one-step recipe.
    function _resep(uint8 a, uint8 b) internal pure returns (uint8[] memory r) {
        r = new uint8[](b == 0 ? 1 : 2);
        r[0] = a;
        if (b != 0) r[1] = b;
    }
}
