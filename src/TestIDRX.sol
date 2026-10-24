// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title TestIDRX (tIDRX) — token SIMULASI Rupiah untuk testnet
/// @notice Bukan IDRX asli dan tidak terkait penerbit IDRX. IDRX asli ada di Monad mainnet
/// (`0x18Bc5bcC660cf2B9cE3cd51a404aFe1a0cBD3C22`, 2 desimal) tetapi tidak di testnet dan tidak mendukung `permit`.
/// Token ini meniru desimalnya (1 tIDRX = Rp1, satuan terkecil Rp0,01) dan menambah `permit` supaya penonton bisa
/// memesan tanpa MON lewat relayer. Dicetak oleh backend top-up (peran MINTER) setelah pembayaran simulasi.
contract TestIDRX is ERC20, ERC20Permit, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(address admin) ERC20("Test IDRX (simulasi)", "tIDRX") ERC20Permit("Test IDRX (simulasi)") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    function decimals() public pure override returns (uint8) {
        return 2;
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
}
