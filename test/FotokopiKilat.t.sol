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

    uint32 constant ANTRE = 45;
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
        fk = new FotokopiKilat("Fotokopi Kilat", "FKL", ANTRE, idrx);
        fk.setKatalog(1, H1, 30, _resep1(FOTOKOPI), "FOTOKOPI KTP");
        fk.setKatalog(2, H1, 30, _resep1(PRINT), "BOARDING PASS");
        fk.setKatalog(3, H3, 45, _resep2(FOTOKOPI, LAMINATING), "LAMINATING IJAZAH");
        fk.setKatalog(4, H3, 45, _resep2(PRINT, LAMINATING), "MENU WARUNG");
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
        id = fk.createOrder(jenis, "Skripsi Bab 1");
    }

    function _status(uint64 id) internal view returns (FotokopiKilat.Status) {
        return fk.getOrder(id).status;
    }

    function _orderAktif(address t) internal view returns (uint64 a) {
        (, a,) = fk.toko(t);
    }

    function _bal(address a) internal view returns (uint256) {
        return idrx.balanceOf(a);
    }

    // ======================================================== BLZ-01.T4

    function test_AdminHanyaOperator() public {
        vm.startPrank(pelanggan);
        vm.expectRevert(FotokopiKilat.NotOperator.selector);
        fk.setKatalog(5, H1, 30, _resep1(PRINT), "X");
        vm.expectRevert(FotokopiKilat.NotOperator.selector);
        fk.registerShop(pelanggan, "X");
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
        fk.setKatalog(0, H1, 30, _resep1(PRINT), "X");
        vm.expectRevert(FotokopiKilat.BadValue.selector);
        fk.setKatalog(5, 0, 30, _resep1(PRINT), "X");
        vm.expectRevert(FotokopiKilat.BadValue.selector);
        fk.setKatalog(5, H1, 0, _resep1(PRINT), "X");
        vm.expectRevert(FotokopiKilat.BadRecipe.selector);
        fk.setKatalog(5, H1, 30, new uint8[](0), "X");
        vm.expectRevert(FotokopiKilat.BadRecipe.selector);
        fk.setKatalog(5, H1, 30, new uint8[](5), "X");
        vm.expectRevert(FotokopiKilat.BadRecipe.selector);
        fk.setKatalog(5, H1, 30, _resep1(4), "X");
        vm.expectRevert(FotokopiKilat.BadText.selector);
        fk.setKatalog(5, H1, 30, _resep1(PRINT), "<b>");
        vm.stopPrank();
    }

    function test_ResepDikemasBerurutan() public view {
        assertEq(fk.langkahKatalog(3, 0), FOTOKOPI);
        assertEq(fk.langkahKatalog(3, 1), LAMINATING);
        assertEq(fk.langkahKatalog(4, 0), PRINT);
        (,,, uint8 n,,) = fk.katalog(4);
        assertEq(n, 2);
    }

    function test_RegisterShop() public {
        vm.startPrank(operator);
        vm.expectRevert(FotokopiKilat.ShopExists.selector);
        fk.registerShop(tokoA, "Lagi");
        vm.expectRevert(FotokopiKilat.BadText.selector);
        fk.registerShop(makeAddr("x"), "Toko \"A\"");
        for (uint256 i = 2; i < fk.MAX_TOKO(); ++i) {
            fk.registerShop(address(uint160(0x1000 + i)), "T");
        }
        vm.expectRevert(FotokopiKilat.TooManyShops.selector);
        fk.registerShop(makeAddr("kesembilan"), "T");
        vm.stopPrank();
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
        fk.createOrder(1, "ok");

        vm.prank(pelanggan);
        vm.expectRevert(FotokopiKilat.BadKind.selector);
        fk.createOrder(9, "ok");

        vm.prank(operator);
        fk.endSession();
        vm.prank(pelanggan);
        vm.expectRevert(FotokopiKilat.SessionClosed.selector);
        fk.createOrder(1, "ok");
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
            fk.createOrder(1, buruk[i]);
        }
        fk.createOrder(1, "1234567890123456789012345678901234567890");
        vm.stopPrank();
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
            abi.encode(fk.PESANAN_TYPEHASH(), p.pelanggan, p.jenis, keccak256(bytes(p.teks)), nonce, p.deadline, p.maxFee)
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
        p = FotokopiKilat.Pesanan(a.addr, jenis, "Ijazah lewat relayer", block.timestamp + 10 minutes, FEE);
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
}
