// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {Test} from "forge-std/Test.sol";
import {FotokopiKilat} from "../src/FotokopiKilat.sol";
import {TestIDRX} from "../src/TestIDRX.sol";

contract FotokopiKilatTest is Test {
    FotokopiKilat fk;
    TestIDRX idrx;

    address operator = makeAddr("operator");
    address tokoA = makeAddr("tokoA");
    address tokoB = makeAddr("tokoB");
    address pelanggan = makeAddr("pelanggan");
    address relayer = makeAddr("relayer");
    address treasury = makeAddr("treasury");

    uint32 constant ANTRE = 45;
    uint32 constant JEMPUT = 600;
    uint32 constant SENGKETA = 1 days;
    bytes32 constant DOK = keccak256("dokumen terenkripsi");
    bytes32 constant RAHASIA = keccak256("rahasia QR pelanggan");
    uint96 constant H1 = 500_000; // Rp5.000 (tIDRX 2 desimal)
    uint96 constant H3 = 1_000_000; // Rp10.000
    uint96 constant FEE = 10_000; // Rp100
    uint256 constant SALDO = 10_000_000; // Rp100.000

    uint8 constant FOTOKOPI = 1;
    uint8 constant PRINT = 2;
    uint8 constant LAMINATING = 3;

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        vm.warp(1_000_000);
        vm.startPrank(operator);
        idrx = new TestIDRX(operator);
        fk = new FotokopiKilat("Fotokopi Kilat", "FKL", ANTRE, JEMPUT, SENGKETA, idrx);
        fk.setKatalog(1, H1, 0, 30, 0, _resep1(FOTOKOPI), "FOTOKOPI KTP");
        fk.setKatalog(2, H1, 0, 30, 0, _resep1(PRINT), "BOARDING PASS");
        fk.setKatalog(3, H3, 0, 45, 0, _resep2(FOTOKOPI, LAMINATING), "LAMINATING IJAZAH");
        fk.setKatalog(4, H3, 0, 45, 0, _resep2(PRINT, LAMINATING), "MENU WARUNG");
        // Rp1.000 + Rp500/halaman, batas 20 dtk + 2 dtk/halaman
        fk.setKatalog(5, 100_000, 50_000, 20, 2, _resep1(PRINT), "PRINT DOKUMEN");
        fk.setFeeRelay(FEE);
        fk.registerShop(tokoA, "Toko A");
        fk.registerShop(tokoB, "Toko B");
        fk.startSession();
        idrx.mint(pelanggan, SALDO);
        vm.stopPrank();
        vm.prank(pelanggan);
        idrx.approve(address(fk), type(uint256).max);
    }

    // ---------------------------------------------------------------- helper

    function _resep1(uint8 a) internal pure returns (uint8[] memory r) {
        r = new uint8[](1);
        r[0] = a;
    }

    function _resep2(uint8 a, uint8 b) internal pure returns (uint8[] memory r) {
        r = new uint8[](2);
        r[0] = a;
        r[1] = b;
    }

    function _pesan(uint8 jenis) internal returns (uint64 id) {
        vm.prank(pelanggan);
        id = fk.createOrder(jenis, "Skripsi Bab 1", 1, bytes32(0), bytes32(0));
    }

    /// @dev Order nyata: dokumen + kode serah terima.
    function _pesanKode(uint8 jenis, uint16 halaman) internal returns (uint64 id) {
        vm.prank(pelanggan);
        id = fk.createOrder(jenis, "Skripsi Bab 1", halaman, DOK, keccak256(abi.encodePacked(RAHASIA)));
    }

    /// @dev Claim + kerjakan semua langkah setelah `detik`; order berkode berhenti di Siap.
    function _kerjakan(uint64 id, uint256 detik) internal {
        vm.prank(tokoA);
        fk.claim(id);
        vm.warp(block.timestamp + detik);
        FotokopiKilat.Order memory o = fk.getOrder(id);
        vm.startPrank(tokoA);
        for (uint256 i; i < o.jumlahLangkah; ++i) fk.completeStep(id, uint8(o.langkah[i]));
        vm.stopPrank();
    }

    function _status(uint64 id) internal view returns (FotokopiKilat.Status) {
        return fk.getOrder(id).status;
    }

    function _orderAktif(address t) internal view returns (uint64 a) {
        (,, a,) = fk.toko(t);
    }

    function _bal(address a) internal view returns (uint256) {
        return idrx.balanceOf(a);
    }

    // ======================================================== BLZ-01.T4

    function test_AdminHanyaOperator() public {
        vm.startPrank(pelanggan);
        vm.expectRevert(FotokopiKilat.NotOperator.selector);
        fk.setKatalog(6, H1, 0, 30, 0, _resep1(PRINT), "X");
        vm.expectRevert(FotokopiKilat.NotOperator.selector);
        fk.registerShop(pelanggan, "X");
        vm.expectRevert(FotokopiKilat.NotOperator.selector);
        fk.putuskan(1, 0);
        vm.expectRevert(FotokopiKilat.NotOperator.selector);
        fk.setPlatform(300, treasury, 1);
        vm.expectRevert(FotokopiKilat.NotOperator.selector);
        fk.startSession();
        vm.expectRevert(FotokopiKilat.NotOperator.selector);
        fk.endSession();
        vm.expectRevert(FotokopiKilat.NotOperator.selector);
        fk.setFeeRelay(1);
        vm.stopPrank();
    }

    function test_KatalogDivalidasi() public {
        vm.startPrank(operator);
        vm.expectRevert(FotokopiKilat.BadKind.selector);
        fk.setKatalog(0, H1, 0, 30, 0, _resep1(PRINT), "X");
        vm.expectRevert(FotokopiKilat.BadValue.selector);
        fk.setKatalog(6, 0, 0, 30, 0, _resep1(PRINT), "X");
        vm.expectRevert(FotokopiKilat.BadValue.selector);
        fk.setKatalog(6, H1, 0, 0, 0, _resep1(PRINT), "X");
        vm.expectRevert(FotokopiKilat.BadValue.selector); // 500 halaman tidak muat di uint96
        fk.setKatalog(6, 0, type(uint96).max / 400, 30, 0, _resep1(PRINT), "X");
        vm.expectRevert(FotokopiKilat.BadValue.selector); // 500 halaman tidak muat di uint32
        fk.setKatalog(6, H1, 0, 30, type(uint32).max / 400, _resep1(PRINT), "X");
        vm.expectRevert(FotokopiKilat.BadRecipe.selector);
        fk.setKatalog(6, H1, 0, 30, 0, new uint8[](0), "X");
        vm.expectRevert(FotokopiKilat.BadRecipe.selector);
        fk.setKatalog(6, H1, 0, 30, 0, new uint8[](5), "X");
        vm.expectRevert(FotokopiKilat.BadRecipe.selector);
        fk.setKatalog(6, H1, 0, 30, 0, _resep1(4), "X");
        vm.expectRevert(FotokopiKilat.BadText.selector);
        fk.setKatalog(6, H1, 0, 30, 0, _resep1(PRINT), "<b>");
        vm.stopPrank();
    }

    function test_ResepDikemasBerurutan() public view {
        assertEq(fk.langkahKatalog(3, 0), FOTOKOPI);
        assertEq(fk.langkahKatalog(3, 1), LAMINATING);
        assertEq(fk.langkahKatalog(4, 0), PRINT);
        (,,,,, uint8 n,,) = fk.katalog(4);
        assertEq(n, 2);
    }

    function test_RegisterShop() public {
        vm.startPrank(operator);
        vm.expectRevert(FotokopiKilat.ShopExists.selector);
        fk.registerShop(tokoA, "Lagi");
        vm.expectRevert(FotokopiKilat.BadText.selector);
        fk.registerShop(makeAddr("x"), "Toko \"A\"");
        for (uint256 i = 0; i < 20; ++i) fk.registerShop(address(uint160(0x1000 + i)), "T"); // tanpa batas 8 toko
        vm.stopPrank();
        assertEq(fk.jumlahToko(), 22);
    }

    function test_TokoDaftarSendiri() public {
        address tokoC = makeAddr("tokoC");
        vm.expectEmit(true, false, false, true);
        emit FotokopiKilat.ShopRegistered(tokoC, "Fotokopi Barokah");
        vm.prank(tokoC);
        fk.daftarkanToko("Fotokopi Barokah");
        (bool terdaftar, bool aktif,, string memory nama) = fk.toko(tokoC);
        assertTrue(terdaftar && aktif);
        assertEq(nama, "Fotokopi Barokah");
        vm.prank(tokoC);
        vm.expectRevert(FotokopiKilat.ShopExists.selector);
        fk.daftarkanToko("Lagi");
        vm.prank(tokoC);
        fk.ubahNamaToko("Barokah Copy Center");
        (,,, nama) = fk.toko(tokoC);
        assertEq(nama, "Barokah Copy Center");
        vm.prank(pelanggan);
        vm.expectRevert(FotokopiKilat.NotShop.selector);
        fk.ubahNamaToko("X");
        uint64 id = _pesan(1);
        vm.prank(tokoC);
        fk.claim(id); // toko yang daftar sendiri langsung bisa rebutan
    }

    function test_TokoDinonaktifkan() public {
        vm.prank(pelanggan);
        vm.expectRevert(FotokopiKilat.NotOperator.selector);
        fk.setTokoAktif(tokoA, false);
        vm.prank(operator);
        fk.setTokoAktif(tokoA, false);
        uint64 id = _pesan(1);
        vm.prank(tokoA);
        vm.expectRevert(FotokopiKilat.ShopInactive.selector);
        fk.claim(id);
        vm.prank(operator);
        fk.setTokoAktif(tokoA, true);
        vm.prank(tokoA);
        fk.claim(id);
        vm.prank(operator);
        vm.expectRevert(FotokopiKilat.NotShop.selector);
        fk.setTokoAktif(pelanggan, true);
    }

    function test_Sesi() public {
        assertEq(fk.sesiId(), 1);
        vm.startPrank(operator);
        vm.expectRevert(FotokopiKilat.SessionOpen.selector);
        fk.startSession();
        fk.endSession();
        vm.expectRevert(FotokopiKilat.SessionClosed.selector);
        fk.endSession();
        fk.startSession();
        vm.stopPrank();
        assertEq(fk.sesiId(), 2);
    }

    function test_TokenSimulasi() public view {
        assertEq(idrx.decimals(), 2);
        assertEq(idrx.symbol(), "tIDRX");
        assertEq(address(fk.token()), address(idrx));
    }

    // ======================================================== BLZ-02.T3

    function test_CreateOrder_Escrow() public {
        uint64 id = _pesan(1);
        assertEq(id, 1);
        assertEq(_bal(address(fk)), H1);
        assertEq(_bal(pelanggan), SALDO - H1);
        assertEq(uint8(_status(id)), uint8(FotokopiKilat.Status.Open));
    }

    function test_CreateOrder_Ditolak() public {
        address tanpaIzin = makeAddr("tanpaIzin");
        vm.prank(operator);
        idrx.mint(tanpaIzin, SALDO);
        vm.prank(tanpaIzin);
        vm.expectRevert(); // ERC20InsufficientAllowance
        fk.createOrder(1, "ok", 1, 0, 0);

        vm.prank(pelanggan);
        vm.expectRevert(FotokopiKilat.BadKind.selector);
        fk.createOrder(9, "ok", 1, 0, 0);

        vm.startPrank(pelanggan);
        vm.expectRevert(FotokopiKilat.BadPages.selector);
        fk.createOrder(1, "ok", 0, 0, 0);
        vm.expectRevert(FotokopiKilat.BadPages.selector);
        fk.createOrder(1, "ok", 501, 0, 0);
        vm.stopPrank();

        vm.prank(operator);
        fk.endSession();
        vm.prank(pelanggan);
        vm.expectRevert(FotokopiKilat.SessionClosed.selector);
        fk.createOrder(1, "ok", 1, 0, 0);
    }

    function test_CreateOrder_TeksTidakValid() public {
        string[8] memory buruk = [
            "",
            "12345678901234567890123456789012345678901",
            "<script>",
            "a&b",
            "kata \"kutip\"",
            "it's",
            "back\\slash",
            "emoji \xf0\x9f\x98\x80"
        ];
        vm.startPrank(pelanggan);
        for (uint256 i; i < buruk.length; ++i) {
            vm.expectRevert(FotokopiKilat.BadText.selector);
            fk.createOrder(1, buruk[i], 1, 0, 0);
        }
        fk.createOrder(1, "1234567890123456789012345678901234567890", 1, 0, 0);
        vm.stopPrank();
    }

    // ======================================================== BLZ-24 harga per halaman + BLZ-21.T5 dokumen

    function test_HargaDanBatasPerHalaman() public {
        (uint96 harga, uint32 batas) = fk.hargaUntuk(5, 10);
        assertEq(harga, 100_000 + 50_000 * 10); // Rp6.000
        assertEq(batas, 20 + 2 * 10);
        uint256 sebelum = _bal(pelanggan);
        uint64 id = _pesanKode(5, 10);
        assertEq(sebelum - _bal(pelanggan), harga, "ditarik sesuai hargaUntuk");
        FotokopiKilat.Order memory o = fk.getOrder(id);
        assertEq(o.harga, harga);
        assertEq(o.batasKerja, batas);
        assertEq(o.halaman, 10);
        (harga, batas) = fk.hargaUntuk(5, 500);
        assertEq(harga, 100_000 + 50_000 * 500);
        assertEq(batas, 20 + 2 * 500);
    }

    function test_DokumenDanKodeTersimpan() public {
        bytes32 kode = keccak256(abi.encodePacked(RAHASIA));
        vm.expectEmit(true, false, false, true);
        emit FotokopiKilat.OrderDetail(1, 3, 26, DOK, kode);
        uint64 id = _pesanKode(5, 3);
        FotokopiKilat.Order memory o = fk.getOrder(id);
        assertEq(o.dokumen, DOK);
        assertEq(o.kodeHash, kode);
        assertEq(fk.getOrder(_pesan(1)).kodeHash, bytes32(0), "mode demo tanpa kode");
    }

    // ======================================================== BLZ-23 siap + serah terima

    function test_Siap_PayoutTerkunciDanTokoBebas() public {
        uint64 id = _pesanKode(1, 1);
        _kerjakan(id, 10);
        assertEq(uint8(_status(id)), uint8(FotokopiKilat.Status.Siap));
        assertEq(_orderAktif(tokoA), 0, "toko bebas setelah siap");
        assertEq(_bal(address(fk)), H1, "dana masih di escrow");
        uint256 terkunci = fk.payoutSekarang(id);
        assertEq(terkunci, uint256(H1) * 20 / 30);
        vm.warp(block.timestamp + 300);
        assertEq(fk.payoutSekarang(id), terkunci, "payout tidak turun setelah siap");
        uint64 lain = _pesan(1);
        vm.prank(tokoA);
        fk.claim(lain);
    }

    function test_Serahkan() public {
        uint64 id = _pesanKode(1, 1);
        _kerjakan(id, 10);
        vm.warp(block.timestamp + 120); // pelanggan datang 2 menit kemudian
        vm.prank(tokoA);
        vm.expectRevert(FotokopiKilat.BadCode.selector);
        fk.serahkan(id, keccak256("salah"));
        vm.prank(tokoB);
        vm.expectRevert(FotokopiKilat.NotYourOrder.selector);
        fk.serahkan(id, RAHASIA);

        uint256 payout = uint256(H1) * 20 / 30;
        uint256 tokoSebelum = _bal(tokoA);
        uint256 pelangganSebelum = _bal(pelanggan);
        vm.expectEmit(true, true, false, true);
        emit FotokopiKilat.OrderFinished(id, tokoA, payout, H1 - payout, 10, true);
        vm.prank(tokoA);
        fk.serahkan(id, RAHASIA);
        assertEq(_bal(tokoA) - tokoSebelum, payout);
        assertEq(_bal(pelanggan) - pelangganSebelum, H1 - payout, "cashback");
        assertEq(fk.ownerOf(id), pelanggan);
        assertEq(_bal(address(fk)), 0);
        vm.prank(tokoA);
        vm.expectRevert(FotokopiKilat.NotReady.selector);
        fk.serahkan(id, RAHASIA);
    }

    function test_Siap_TidakDijemput() public {
        uint64 id = _pesanKode(3, 1);
        _kerjakan(id, 9);
        vm.warp(block.timestamp + JEMPUT - 1);
        vm.expectRevert(FotokopiKilat.NotExpired.selector);
        fk.expire(id);
        vm.warp(block.timestamp + 1);
        uint256 payout = uint256(H3) * 36 / 45;
        vm.expectEmit(true, true, false, true);
        emit FotokopiKilat.OrderFinished(id, tokoA, payout, H3 - payout, 9, false);
        fk.expire(id);
        assertEq(uint8(_status(id)), uint8(FotokopiKilat.Status.Finished));
        assertEq(fk.ownerOf(id), pelanggan);
        assertEq(_bal(address(fk)), 0);
    }

    function test_Komplain_DanPutuskan() public {
        uint64 id = _pesanKode(1, 1);
        _kerjakan(id, 10);
        vm.prank(tokoA);
        vm.expectRevert(FotokopiKilat.NotCustomer.selector);
        fk.komplain(id);
        vm.expectEmit(true, false, false, false);
        emit FotokopiKilat.OrderDisputed(id);
        vm.prank(pelanggan);
        fk.komplain(id);
        assertEq(uint8(_status(id)), uint8(FotokopiKilat.Status.Sengketa));

        vm.prank(tokoA);
        vm.expectRevert(FotokopiKilat.NotReady.selector);
        fk.serahkan(id, RAHASIA);
        vm.warp(block.timestamp + JEMPUT * 2);
        vm.expectRevert(FotokopiKilat.NotExpired.selector);
        fk.expire(id);

        vm.startPrank(operator);
        vm.expectRevert(FotokopiKilat.BadShare.selector);
        fk.putuskan(id, 10_001);
        uint256 bagian = uint256(H1) * 20 / 30 / 2;
        uint256 tokoSebelum = _bal(tokoA);
        uint256 pelangganSebelum = _bal(pelanggan);
        fk.putuskan(id, 5_000);
        vm.expectRevert(FotokopiKilat.NotDisputed.selector);
        fk.putuskan(id, 5_000);
        vm.stopPrank();
        assertEq(_bal(tokoA) - tokoSebelum, bagian);
        assertEq(_bal(pelanggan) - pelangganSebelum, H1 - bagian);
        assertEq(uint8(_status(id)), uint8(FotokopiKilat.Status.Diputuskan));
        assertEq(fk.balanceOf(pelanggan), 0, "sengketa tanpa NFT");
        assertEq(fk.omzet(1, tokoA), bagian);
        assertEq(_bal(address(fk)), 0);
    }

    function test_Komplain_TerlambatAtauBukanSiap() public {
        uint64 id = _pesanKode(1, 1);
        vm.prank(pelanggan);
        vm.expectRevert(FotokopiKilat.NotReady.selector);
        fk.komplain(id);
        _kerjakan(id, 5);
        vm.warp(block.timestamp + JEMPUT);
        vm.prank(pelanggan);
        vm.expectRevert(FotokopiKilat.TooLate.selector);
        fk.komplain(id);
    }

    // ======================================================== BLZ-03.T2

    function test_Claim_Rebutan() public {
        uint64 id = _pesan(1);
        vm.prank(tokoA);
        fk.claim(id);
        vm.prank(tokoB);
        vm.expectRevert(FotokopiKilat.AlreadyClaimed.selector);
        fk.claim(id);
        assertEq(_orderAktif(tokoA), id);
    }

    function test_Claim_TokoSibukDanBukanToko() public {
        uint64 a = _pesan(1);
        uint64 b = _pesan(2);
        vm.startPrank(tokoA);
        fk.claim(a);
        vm.expectRevert(FotokopiKilat.ShopBusy.selector);
        fk.claim(b);
        vm.stopPrank();
        vm.prank(pelanggan);
        vm.expectRevert(FotokopiKilat.NotShop.selector);
        fk.claim(b);
    }

    function test_Claim_BatasAntre() public {
        uint64 id = _pesan(1);
        vm.warp(block.timestamp + ANTRE);
        vm.prank(tokoA);
        vm.expectRevert(FotokopiKilat.QueueTimeout.selector);
        fk.claim(id);
    }

    // ======================================================== BLZ-04.T3

    function test_CompleteStep_Validasi() public {
        uint64 id = _pesan(3);
        vm.prank(tokoA);
        vm.expectRevert(FotokopiKilat.NotClaimed.selector);
        fk.completeStep(id, FOTOKOPI);
        vm.prank(tokoA);
        fk.claim(id);
        vm.prank(tokoB);
        vm.expectRevert(FotokopiKilat.NotYourOrder.selector);
        fk.completeStep(id, FOTOKOPI);
        vm.prank(tokoA);
        vm.expectRevert(FotokopiKilat.WrongStep.selector);
        fk.completeStep(id, LAMINATING);
        vm.warp(block.timestamp + 45);
        vm.prank(tokoA);
        vm.expectRevert(FotokopiKilat.Late.selector);
        fk.completeStep(id, FOTOKOPI);
    }

    function _selesaiSetelah(uint8 jenis, uint256 detik) internal returns (uint64 id) {
        id = _pesan(jenis);
        vm.prank(tokoA);
        fk.claim(id);
        vm.warp(block.timestamp + detik);
        vm.startPrank(tokoA);
        fk.completeStep(id, fk.langkahKatalog(jenis, 0));
        if (jenis >= 3) fk.completeStep(id, LAMINATING);
        vm.stopPrank();
    }

    function test_Payout_TitikTitik() public {
        uint256[4] memory detik = [uint256(0), 11, 15, 44];
        for (uint256 i; i < detik.length; ++i) {
            uint256 tokoSebelum = _bal(tokoA);
            uint256 pelangganSebelum = _bal(pelanggan);
            uint64 id = _selesaiSetelah(3, detik[i]);
            uint256 payout = uint256(H3) * (45 - detik[i]) / 45;
            assertEq(_bal(tokoA) - tokoSebelum, payout, "payout");
            assertEq(_bal(pelanggan) + H3 - pelangganSebelum, H3 - payout, "refund");
            assertEq(fk.ownerOf(id), pelanggan);
            assertEq(_orderAktif(tokoA), 0);
        }
        assertEq(_bal(address(fk)), 0);
        (address w, uint256 o) = fk.pemenang(1);
        assertEq(w, tokoA);
        assertEq(o, fk.omzet(1, tokoA));
    }

    function testFuzz_PayoutPlusRefundSamaHarga(uint256 detik) public {
        detik = bound(detik, 0, 29);
        uint256 awal = _bal(tokoA) + _bal(pelanggan);
        _selesaiSetelah(1, detik);
        assertEq(_bal(tokoA) + _bal(pelanggan), awal, "token hilang atau tercipta");
        assertEq(_bal(address(fk)), 0);
    }

    function test_PayoutSekarang_SamaDenganBayaran() public {
        uint64 id = _pesan(1);
        vm.prank(tokoA);
        fk.claim(id);
        vm.warp(block.timestamp + 10);
        uint256 perkiraan = fk.payoutSekarang(id);
        uint256 sebelum = _bal(tokoA);
        vm.prank(tokoA);
        fk.completeStep(id, FOTOKOPI);
        assertEq(_bal(tokoA) - sebelum, perkiraan);
    }

    // ======================================================== BLZ-05.T3

    function test_Expire_Antre() public {
        uint64 id = _pesan(1);
        vm.expectRevert(FotokopiKilat.NotExpired.selector);
        fk.expire(id);
        vm.warp(block.timestamp + ANTRE);
        uint256 sebelum = _bal(pelanggan);
        vm.expectEmit(true, false, false, true);
        emit FotokopiKilat.OrderExpired(id, H1, FotokopiKilat.AlasanExpire.Antre);
        fk.expire(id);
        assertEq(_bal(pelanggan) - sebelum, H1);
        assertEq(uint8(_status(id)), uint8(FotokopiKilat.Status.Expired));
    }

    function test_Expire_Kerja_RefundPenuhDanClaimUlang() public {
        uint64 id = _pesan(3);
        vm.prank(tokoA);
        fk.claim(id);
        vm.prank(tokoA);
        fk.completeStep(id, FOTOKOPI);
        vm.warp(block.timestamp + 45);
        fk.expire(id);
        assertEq(_bal(pelanggan), SALDO, "refund harus penuh");
        assertEq(_bal(address(fk)), 0);
        uint64 baru = _pesan(1);
        vm.prank(tokoA);
        fk.claim(baru);
        assertEq(_orderAktif(tokoA), baru);
    }

    function test_Expire_OrderSelesaiTidakBisa() public {
        uint64 id = _selesaiSetelah(1, 5);
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(FotokopiKilat.NotExpired.selector);
        fk.expire(id);
    }

    // ======================================================== BLZ-06.T3

    function test_TokenURI() public {
        uint64 id = _selesaiSetelah(4, 12);
        string memory uri = fk.tokenURI(id);
        assertGt(bytes(uri).length, 500);
        vm.expectRevert();
        fk.tokenURI(id + 1);
    }

    // ======================================================== BLZ-18.T3 relay (pesan tanpa MON)

    struct Akun {
        address addr;
        uint256 key;
    }

    function _akunBaru(string memory nama) internal returns (Akun memory a) {
        (a.addr, a.key) = makeAddrAndKey(nama);
        vm.deal(a.addr, 0); // tidak punya MON sama sekali
        vm.prank(operator);
        idrx.mint(a.addr, SALDO);
    }

    function _tandaPesanan(uint256 key, FotokopiKilat.Pesanan memory p, uint256 nonce) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                fk.PESANAN_TYPEHASH(),
                p.pelanggan,
                p.jenis,
                keccak256(bytes(p.teks)),
                p.halaman,
                p.dokumen,
                p.kodeHash,
                nonce,
                p.deadline,
                p.maxFee
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, keccak256(abi.encodePacked("\x19\x01", fk.domainSeparator(), structHash)));
        return abi.encodePacked(r, s, v);
    }

    function _izin(Akun memory a, uint256 value) internal view returns (FotokopiKilat.Izin memory z) {
        z.value = value;
        z.deadline = block.timestamp + 1 hours;
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, a.addr, address(fk), value, idrx.nonces(a.addr), z.deadline));
        (z.v, z.r, z.s) = vm.sign(a.key, keccak256(abi.encodePacked("\x19\x01", idrx.DOMAIN_SEPARATOR(), structHash)));
    }

    function _pesanan(Akun memory a, uint8 jenis) internal view returns (FotokopiKilat.Pesanan memory p) {
        p = FotokopiKilat.Pesanan(
            a.addr, jenis, "Ijazah lewat relayer", 1, bytes32(0), bytes32(0), block.timestamp + 10 minutes, FEE
        );
    }

    function test_Relay_PesanTanpaMON() public {
        Akun memory a = _akunBaru("penonton");
        FotokopiKilat.Pesanan memory p = _pesanan(a, 3);
        bytes memory sig = _tandaPesanan(a.key, p, 0);
        FotokopiKilat.Izin memory z = _izin(a, H3 + FEE);
        // helper di atas memanggil contract; prank harus tepat sebelum createOrderFor
        vm.prank(relayer);
        uint64 id = fk.createOrderFor(p, sig, z);
        assertEq(fk.getOrder(id).pelanggan, a.addr);
        assertEq(_bal(address(fk)), H3);
        assertEq(_bal(relayer), FEE, "relayer menerima fee");
        assertEq(_bal(a.addr), SALDO - H3 - FEE);
        assertEq(fk.nonces(a.addr), 1);
        assertEq(a.addr.balance, 0, "penonton tetap tanpa MON");
    }

    function test_Relay_TandaTanganPalsuDanTeksDiubah() public {
        Akun memory a = _akunBaru("penonton");
        Akun memory b = _akunBaru("penyusup");
        FotokopiKilat.Pesanan memory p = _pesanan(a, 1);
        FotokopiKilat.Izin memory z = _izin(a, H1 + FEE);
        bytes memory palsu = _tandaPesanan(b.key, p, 0);
        vm.prank(relayer);
        vm.expectRevert(FotokopiKilat.BadSignature.selector);
        fk.createOrderFor(p, palsu, z);

        bytes memory asli = _tandaPesanan(a.key, p, 0);
        p.teks = "Teks diubah relayer";
        vm.prank(relayer);
        vm.expectRevert(FotokopiKilat.BadSignature.selector);
        fk.createOrderFor(p, asli, z);
    }

    function test_Relay_TidakBisaDiulang() public {
        Akun memory a = _akunBaru("penonton");
        FotokopiKilat.Pesanan memory p = _pesanan(a, 1);
        bytes memory sig = _tandaPesanan(a.key, p, 0);
        FotokopiKilat.Izin memory z = _izin(a, type(uint256).max);
        vm.prank(relayer);
        fk.createOrderFor(p, sig, z);
        vm.prank(relayer);
        vm.expectRevert(FotokopiKilat.BadSignature.selector);
        fk.createOrderFor(p, sig, FotokopiKilat.Izin(0, 0, 0, 0, 0));
    }

    function test_Relay_KedaluwarsaDanFee() public {
        Akun memory a = _akunBaru("penonton");
        FotokopiKilat.Pesanan memory p = _pesanan(a, 1);
        bytes memory sig = _tandaPesanan(a.key, p, 0);
        FotokopiKilat.Izin memory z = _izin(a, H1 + FEE);
        vm.warp(p.deadline + 1);
        vm.prank(relayer);
        vm.expectRevert(FotokopiKilat.SignatureExpired.selector);
        fk.createOrderFor(p, sig, z);

        vm.warp(1_000_000);
        vm.prank(operator);
        fk.setFeeRelay(FEE + 1);
        vm.prank(relayer);
        vm.expectRevert(FotokopiKilat.FeeTooHigh.selector);
        fk.createOrderFor(p, sig, z);
    }

    function test_Relay_PermitSudahDipakaiOrangLain() public {
        Akun memory a = _akunBaru("penonton");
        FotokopiKilat.Pesanan memory p = _pesanan(a, 1);
        FotokopiKilat.Izin memory z = _izin(a, H1 + FEE);
        // penyerang memakai permit lebih dulu (front-run); createOrderFor tetap jalan karena allowance sudah ada
        idrx.permit(a.addr, address(fk), z.value, z.deadline, z.v, z.r, z.s);
        bytes memory sig = _tandaPesanan(a.key, p, 0);
        vm.prank(relayer);
        uint64 id = fk.createOrderFor(p, sig, z);
        assertEq(_bal(relayer), FEE);
        assertEq(fk.getOrder(id).pelanggan, a.addr);
    }

    function test_Relay_TanpaPermitBilaAllowanceAda() public {
        Akun memory a = _akunBaru("penonton");
        vm.prank(a.addr);
        idrx.approve(address(fk), type(uint256).max);
        FotokopiKilat.Pesanan memory p = _pesanan(a, 2);
        bytes memory sig = _tandaPesanan(a.key, p, 0);
        vm.prank(relayer);
        fk.createOrderFor(p, sig, FotokopiKilat.Izin(0, 0, 0, 0, 0));
        assertEq(_bal(relayer), FEE);
        assertEq(_bal(address(fk)), H1);
    }

    function test_Relay_OrderNyataDenganKodeDanHalaman() public {
        Akun memory a = _akunBaru("penonton");
        FotokopiKilat.Pesanan memory p = _pesanan(a, 5);
        p.halaman = 8;
        p.dokumen = DOK;
        p.kodeHash = keccak256(abi.encodePacked(RAHASIA));
        (uint96 harga,) = fk.hargaUntuk(5, 8);
        bytes memory sig = _tandaPesanan(a.key, p, 0);
        FotokopiKilat.Izin memory z = _izin(a, harga + FEE);
        vm.prank(relayer);
        uint64 id = fk.createOrderFor(p, sig, z);
        FotokopiKilat.Order memory o = fk.getOrder(id);
        assertEq(o.halaman, 8);
        assertEq(o.dokumen, DOK);
        assertEq(o.harga, harga);
        // halaman diubah relayer → tanda tangan tidak cocok
        p.halaman = 1;
        sig = _tandaPesanan(a.key, p, 1);
        p.halaman = 2;
        vm.prank(relayer);
        vm.expectRevert(FotokopiKilat.BadSignature.selector);
        fk.createOrderFor(p, sig, FotokopiKilat.Izin(0, 0, 0, 0, 0));
    }

    // ======================================================== revenue v2.1: platform fee + Toko Pro

    function test_SetPlatform_Validasi() public {
        vm.startPrank(operator);
        vm.expectRevert(FotokopiKilat.BadShare.selector);
        fk.setPlatform(1_001, treasury, 0);
        vm.expectRevert(FotokopiKilat.BadValue.selector);
        fk.setPlatform(300, address(0), 0);
        vm.expectEmit(false, false, false, true);
        emit FotokopiKilat.PlatformSet(300, treasury, 5_000_000);
        fk.setPlatform(300, treasury, 5_000_000);
        vm.stopPrank();
        assertEq(fk.platformFeeBps(), 300);
        assertEq(fk.treasury(), treasury);
    }

    function test_PlatformFee_DariPayoutToko() public {
        vm.prank(operator);
        fk.setPlatform(300, treasury, 0);
        uint256 tokoSebelum = _bal(tokoA);
        uint256 pelangganSebelum = _bal(pelanggan);
        uint64 id = _pesanKode(1, 1);
        _kerjakan(id, 10);
        uint256 payout = uint256(H1) * 20 / 30;
        uint256 fee = payout * 300 / 10_000;
        vm.expectEmit(true, false, false, true);
        emit FotokopiKilat.PlatformFeeTaken(id, fee);
        vm.prank(tokoA);
        fk.serahkan(id, RAHASIA);
        assertEq(_bal(treasury), fee, "treasury dapat 3% payout");
        assertEq(_bal(tokoA) - tokoSebelum, payout - fee, "toko dapat payout bersih");
        assertEq(pelangganSebelum - _bal(pelanggan), payout, "cashback pelanggan tidak terpotong fee");
        assertEq(fk.omzet(1, tokoA), payout - fee);
        assertEq(_bal(address(fk)), 0);
    }

    function test_PlatformFee_TidakAdaSaatExpire() public {
        vm.prank(operator);
        fk.setPlatform(300, treasury, 0);
        uint64 id = _pesan(1);
        vm.warp(block.timestamp + ANTRE);
        fk.expire(id);
        assertEq(_bal(treasury), 0, "order gagal tidak dipotong");
        assertEq(_bal(pelanggan), SALDO, "refund penuh");
    }

    function test_PlatformFee_SaatPutuskan() public {
        vm.prank(operator);
        fk.setPlatform(500, treasury, 0);
        uint64 id = _pesanKode(1, 1);
        _kerjakan(id, 10);
        vm.prank(pelanggan);
        fk.komplain(id);
        vm.prank(operator);
        fk.putuskan(id, 10_000);
        uint256 payout = uint256(H1) * 20 / 30;
        assertEq(_bal(treasury), payout * 500 / 10_000);
        assertEq(_bal(address(fk)), 0);
    }

    function test_TokoPro() public {
        vm.prank(tokoA);
        vm.expectRevert(FotokopiKilat.BadValue.selector); // harga Pro belum diatur
        fk.langgananPro(1);
        vm.prank(operator);
        fk.setPlatform(300, treasury, 5_000_000); // Rp50.000 / 30 hari
        vm.prank(operator);
        idrx.mint(tokoA, 20_000_000);
        vm.startPrank(tokoA);
        idrx.approve(address(fk), type(uint256).max);
        vm.expectRevert(FotokopiKilat.BadValue.selector);
        fk.langgananPro(13);
        assertFalse(fk.isPro(tokoA));
        vm.expectEmit(true, false, false, true);
        emit FotokopiKilat.ProSubscribed(tokoA, uint40(block.timestamp + 60 days), 10_000_000);
        fk.langgananPro(2);
        assertTrue(fk.isPro(tokoA));
        fk.langgananPro(1); // diperpanjang dari tanggal berakhir, bukan dari sekarang
        vm.stopPrank();
        assertEq(fk.proSampai(tokoA), block.timestamp + 90 days);
        assertEq(_bal(treasury), 15_000_000);
        vm.warp(block.timestamp + 90 days);
        assertFalse(fk.isPro(tokoA));

        vm.prank(pelanggan);
        vm.expectRevert(FotokopiKilat.NotShop.selector);
        fk.langgananPro(1);
    }

    // ======================================================== v2.2 batas waktu sengketa

    function test_TutupSengketa_SetelahBatas() public {
        vm.prank(operator);
        fk.setPlatform(300, treasury, 0);
        uint64 id = _pesanKode(1, 1);
        _kerjakan(id, 10);
        uint256 siap = block.timestamp;
        vm.prank(pelanggan);
        fk.komplain(id);
        vm.warp(siap + JEMPUT + SENGKETA - 1);
        vm.expectRevert(FotokopiKilat.NotExpired.selector);
        fk.tutupSengketa(id);
        vm.warp(siap + JEMPUT + SENGKETA);
        uint256 payout = uint256(H1) * 20 / 30 / 2; // bagian default 50%
        uint256 fee = payout * 300 / 10_000;
        uint256 tokoSebelum = _bal(tokoA);
        uint256 pelangganSebelum = _bal(pelanggan);
        vm.expectEmit(true, true, false, true);
        emit FotokopiKilat.DisputeResolved(id, tokoA, payout - fee, H1 - payout, true);
        fk.tutupSengketa(id); // siapa saja (keeper)
        assertEq(_bal(tokoA) - tokoSebelum, payout - fee);
        assertEq(_bal(pelanggan) - pelangganSebelum, H1 - payout);
        assertEq(_bal(treasury), fee);
        assertEq(uint8(_status(id)), uint8(FotokopiKilat.Status.Diputuskan));
        assertEq(_bal(address(fk)), 0);
        vm.expectRevert(FotokopiKilat.NotDisputed.selector);
        fk.tutupSengketa(id);
    }

    function test_TutupSengketa_HanyaUntukSengketa() public {
        uint64 id = _pesanKode(1, 1);
        _kerjakan(id, 5);
        vm.warp(block.timestamp + JEMPUT + SENGKETA);
        vm.expectRevert(FotokopiKilat.NotDisputed.selector);
        fk.tutupSengketa(id); // Siap tanpa komplain: ditutup lewat expire, bukan tutupSengketa
        fk.expire(id);
        assertEq(uint8(_status(id)), uint8(FotokopiKilat.Status.Finished));
    }
}
