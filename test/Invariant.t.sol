// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {FotokopiKilat} from "../src/FotokopiKilat.sol";
import {TestIDRX} from "../src/TestIDRX.sol";

/// @dev Aksi acak: pesan (dengan/tanpa kode serah terima), claim, kerjakan, serahkan, komplain, putuskan, expire,
/// majukan waktu. Mencatat id order yang pernah dibuat.
contract Handler is Test {
    FotokopiKilat public immutable fk;
    TestIDRX public immutable idrx;
    address[2] public tokoList;
    address public immutable pelanggan = makeAddr("pelanggan-inv");
    uint64[] public ids;
    mapping(uint64 id => bytes32) public rahasia;
    address public immutable operator;

    constructor(FotokopiKilat fk_, TestIDRX idrx_, address a, address b, address operator_) {
        fk = fk_;
        operator = operator_;
        idrx = idrx_;
        tokoList = [a, b];
        vm.prank(pelanggan);
        idrx.approve(address(fk_), type(uint256).max);
    }

    function jumlahId() external view returns (uint256) {
        return ids.length;
    }

    function pesan(uint8 jenis, uint16 halaman, bool pakaiKode) external {
        jenis = uint8(bound(jenis, 1, 5));
        halaman = uint16(bound(halaman, 1, 500));
        bytes32 r = keccak256(abi.encode(ids.length, "rahasia"));
        vm.prank(pelanggan);
        uint64 id = fk.createOrder(jenis, "inv", halaman, keccak256("dok"), pakaiKode ? keccak256(abi.encodePacked(r)) : bytes32(0));
        ids.push(id);
        if (pakaiKode) rahasia[id] = r;
    }

    function serahkan(uint256 i) external {
        if (ids.length == 0) return;
        uint64 id = ids[bound(i, 0, ids.length - 1)];
        FotokopiKilat.Order memory o = fk.getOrder(id);
        if (o.status != FotokopiKilat.Status.Siap) return;
        vm.prank(o.toko);
        fk.serahkan(id, rahasia[id]);
    }

    function komplain(uint256 i) external {
        if (ids.length == 0) return;
        vm.prank(pelanggan);
        try fk.komplain(ids[bound(i, 0, ids.length - 1)]) {} catch {}
    }

    function tutupSengketa(uint256 i) external {
        if (ids.length == 0) return;
        try fk.tutupSengketa(ids[bound(i, 0, ids.length - 1)]) {} catch {}
    }

    function putuskan(uint256 i, uint16 bagian) external {
        if (ids.length == 0) return;
        vm.prank(operator);
        try fk.putuskan(ids[bound(i, 0, ids.length - 1)], uint16(bound(bagian, 0, 10_000))) {} catch {}
    }

    function claim(uint256 i, uint256 t) external {
        if (ids.length == 0) return;
        uint64 id = ids[bound(i, 0, ids.length - 1)];
        vm.prank(tokoList[t % 2]);
        try fk.claim(id) {} catch {}
    }

    function kerjakan(uint256 i) external {
        if (ids.length == 0) return;
        uint64 id = ids[bound(i, 0, ids.length - 1)];
        FotokopiKilat.Order memory o = fk.getOrder(id);
        if (o.status != FotokopiKilat.Status.Claimed) return;
        uint8 kode = uint8(o.langkah[o.langkahSelesai]);
        vm.prank(o.toko);
        try fk.completeStep(id, kode) {} catch {}
    }

    function expire(uint256 i) external {
        if (ids.length == 0) return;
        try fk.expire(ids[bound(i, 0, ids.length - 1)]) {} catch {}
    }

    function majukan(uint256 detik) external {
        vm.warp(block.timestamp + bound(detik, 1, 400));
    }
}

contract InvariantTest is Test {
    FotokopiKilat fk;
    TestIDRX idrx;
    Handler h;
    address tokoA = makeAddr("inv-tokoA");
    address tokoB = makeAddr("inv-tokoB");
    address treasury = makeAddr("inv-treasury");

    function setUp() public {
        idrx = new TestIDRX(address(this));
        fk = new FotokopiKilat("Fotokopi Kilat", "FKL", 45, 300, 600, idrx);
        uint8[] memory satu = new uint8[](1);
        satu[0] = 1;
        uint8[] memory dua = new uint8[](2);
        (dua[0], dua[1]) = (2, 3);
        fk.setKatalog(1, 500_000, 0, 30, 0, satu, "A");
        fk.setKatalog(2, 500_000, 0, 30, 0, satu, "B");
        fk.setKatalog(3, 1_000_000, 0, 45, 0, dua, "C");
        fk.setKatalog(4, 1_000_000, 0, 45, 0, dua, "D");
        fk.setKatalog(5, 100_000, 50_000, 20, 2, satu, "E");
        fk.setPlatform(300, treasury, 0);
        fk.registerShop(tokoA, "A");
        fk.registerShop(tokoB, "B");
        fk.startSession();
        h = new Handler(fk, idrx, tokoA, tokoB, address(this));
        idrx.mint(h.pelanggan(), 1e15);
        targetContract(address(h));
    }

    /// I-1: saldo token contract = escrow order yang belum final (Open, Claimed, Siap, Sengketa).
    function invariant_SaldoSamaEscrow() public view {
        uint256 escrow;
        uint256 n = h.jumlahId();
        for (uint256 i; i < n; ++i) {
            FotokopiKilat.Order memory o = fk.getOrder(h.ids(i));
            if (
                o.status == FotokopiKilat.Status.Open || o.status == FotokopiKilat.Status.Claimed
                    || o.status == FotokopiKilat.Status.Siap || o.status == FotokopiKilat.Status.Sengketa
            ) escrow += o.harga;
        }
        assertEq(idrx.balanceOf(address(fk)), escrow);
    }

    /// Token tidak tercipta atau hilang: pelanggan + toko + treasury + contract = total suplai.
    function invariant_TokenKekal() public view {
        assertEq(
            idrx.balanceOf(h.pelanggan()) + idrx.balanceOf(tokoA) + idrx.balanceOf(tokoB) + idrx.balanceOf(treasury)
                + idrx.balanceOf(address(fk)),
            idrx.totalSupply()
        );
    }

    /// I-3: tiap toko paling banyak satu order Claimed, dan itu sama dengan `orderAktif`.
    function invariant_SatuOrderAktifPerToko() public view {
        address[2] memory ts = [tokoA, tokoB];
        for (uint256 k; k < 2; ++k) {
            uint256 aktif;
            uint64 terakhir;
            uint256 n = h.jumlahId();
            for (uint256 i; i < n; ++i) {
                uint64 id = h.ids(i);
                FotokopiKilat.Order memory o = fk.getOrder(id);
                if (o.status == FotokopiKilat.Status.Claimed && o.toko == ts[k]) {
                    ++aktif;
                    terakhir = id;
                }
            }
            (, uint64 orderAktif,) = fk.toko(ts[k]);
            assertLe(aktif, 1);
            assertEq(orderAktif, terakhir);
        }
    }

    /// I-6: jumlah NFT = jumlah order Finished, semuanya milik pelanggan.
    function invariant_NftHanyaUntukFinished() public view {
        uint256 selesai;
        uint256 n = h.jumlahId();
        for (uint256 i; i < n; ++i) {
            uint64 id = h.ids(i);
            if (fk.getOrder(id).status == FotokopiKilat.Status.Finished) {
                ++selesai;
                assertEq(fk.ownerOf(id), h.pelanggan());
            }
        }
        assertEq(fk.balanceOf(h.pelanggan()), selesai);
    }
}
