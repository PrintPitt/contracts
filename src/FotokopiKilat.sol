// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title FotokopiKilat v2 (nama kerja; repo PrintPitt)
/// @notice Order cetak nyata yang di-gamify: pelanggan memesan (jenis, jumlah halaman, hash dokumen terenkripsi) dan
/// membayar ke escrow dalam token Rupiah (tIDRX di testnet); toko rebutan order lalu mengerjakannya langkah demi
/// langkah. Payout turun per detik sampai toko menandai siap; sisanya jadi cashback pelanggan. Dana cair saat serah
/// terima: toko memindai QR rahasia pelanggan (`kodeHash` di order). Order tanpa `kodeHash` (mode demo mini-game)
/// langsung selesai di langkah terakhir. Pelanggan tanpa MON bisa memesan lewat relayer (EIP-712 + permit).
/// Revenue platform (v2.1): `platformFeeBps` dari payout toko saat order selesai, dan langganan Toko Pro, ke `treasury`.
/// Spesifikasi: vault/04-Architecture/Desain Contract.md
contract FotokopiKilat is ERC721, EIP712, ReentrancyGuardTransient {
    using Strings for uint256;
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------------ tipe

    enum Status {
        None,
        Open,
        Claimed,
        Siap, // langkah terakhir selesai, payout terkunci, menunggu serah terima
        Finished,
        Expired,
        Sengketa, // pelanggan komplain saat Siap, menunggu keputusan operator
        Diputuskan
    }

    enum AlasanExpire {
        Antre,
        Kerja
    }

    /// @notice Harga = hargaDasar + hargaPerHalaman × halaman; batas kerja = batasDasar + batasPerHalaman × halaman.
    /// Nominal dalam satuan terkecil token (tIDRX 2 desimal: Rp5.000 = 500000), batas dalam detik.
    struct Katalog {
        uint96 hargaDasar;
        uint96 hargaPerHalaman;
        uint32 batasDasar;
        uint32 batasPerHalaman;
        bytes4 langkah;
        uint8 jumlahLangkah;
        bool aktif;
        string label;
    }

    struct Toko {
        bool terdaftar;
        uint64 orderAktif;
        string nama;
    }

    struct Order {
        address pelanggan;
        uint96 harga;
        address toko;
        uint8 jenis;
        bytes4 langkah;
        uint8 jumlahLangkah;
        uint8 langkahSelesai;
        Status status;
        uint16 halaman;
        uint40 dibuatPada;
        uint40 diclaimPada;
        uint40 siapPada;
        uint32 batasKerja;
        uint32 sesi;
        uint32 kerja; // detik dari claim sampai siap
        bytes32 dokumen; // hash dokumen terenkripsi off-chain (0 = tanpa dokumen, mode demo)
        bytes32 kodeHash; // keccak256(rahasia QR pelanggan); 0 = tanpa serah terima
        string teks;
    }

    /// @notice Pesanan yang ditandatangani pelanggan, dikirim relayer.
    struct Pesanan {
        address pelanggan;
        uint8 jenis;
        string teks;
        uint16 halaman;
        bytes32 dokumen;
        bytes32 kodeHash;
        uint256 deadline;
        uint256 maxFee;
    }

    /// @notice Izin `permit` token (EIP-2612). `deadline == 0` berarti allowance sudah ada, permit dilewati.
    struct Izin {
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    // ------------------------------------------------------------- konstanta

    uint256 public constant MAX_TEXT = 40;
    uint256 public constant MAX_TOKO = 8;
    uint256 public constant MAX_LANGKAH = 4;
    uint8 public constant LANGKAH_TERTINGGI = 3; // 1 Fotokopi, 2 Print, 3 Laminating
    uint16 public constant MAX_HALAMAN = 500;
    uint16 public constant BPS = 10_000;
    uint16 public constant MAX_PLATFORM_FEE_BPS = 1_000; // maks. 10%
    uint256 public constant PERIODE_PRO = 30 days;
    uint8 public constant MAX_PERIODE_PRO = 12;
    /// @notice Pembagian bila operator tidak memutuskan sengketa sampai batas waktu: separuh payout terkunci ke toko.
    uint16 public constant BAGIAN_DEFAULT_SENGKETA = 5_000;

    bytes32 public constant PESANAN_TYPEHASH = keccak256(
        "Pesanan(address pelanggan,uint8 jenis,string teks,uint16 halaman,bytes32 dokumen,bytes32 kodeHash,uint256 nonce,uint256 deadline,uint256 maxFee)"
    );

    // ---------------------------------------------------------------- state

    IERC20 public immutable token;
    address public immutable operator;
    uint32 public immutable batasAntre;
    uint32 public immutable batasJemput; // detik setelah Siap; lewat itu order bisa ditutup tanpa serah terima
    uint32 public immutable batasSengketa; // detik setelah batas jemput; lewat itu sengketa bisa ditutup siapa saja

    uint32 public sesiId;
    bool public sesiAktif;
    uint64 public nextId = 1;
    uint96 public feeRelay; // fee per pesanan lewat relayer, dalam satuan token
    uint16 public platformFeeBps; // potongan platform dari payout toko (hanya order yang selesai)
    address public treasury;
    uint96 public hargaPro; // harga Toko Pro per PERIODE_PRO, dalam satuan token

    mapping(uint8 jenis => Katalog) public katalog;
    mapping(address alamat => Toko) public toko;
    address[] public daftarToko;
    mapping(uint32 sesi => mapping(address toko => uint256)) public omzet;
    mapping(uint64 id => Order) internal order; // dibaca lewat getOrder (getter otomatis 18 nilai = stack too deep)
    mapping(address pelanggan => uint256) public nonces;
    mapping(address toko => uint40) public proSampai;

    // --------------------------------------------------------------- event

    event KatalogSet(
        uint8 indexed jenis,
        uint96 hargaDasar,
        uint96 hargaPerHalaman,
        uint32 batasDasar,
        uint32 batasPerHalaman,
        bytes4 langkah,
        uint8 jumlahLangkah,
        string label
    );
    event ShopRegistered(address indexed toko, string nama);
    event SessionStarted(uint32 indexed sesiId, uint40 waktu);
    event SessionEnded(uint32 indexed sesiId, uint40 waktu);
    event FeeRelaySet(uint96 fee);
    event PlatformSet(uint16 feeBps, address treasury, uint96 hargaPro);
    event PlatformFeeTaken(uint64 indexed id, uint256 fee);
    event ProSubscribed(address indexed toko, uint40 sampai, uint256 bayar);
    event OrderCreated(
        uint64 indexed id, address indexed pelanggan, uint8 jenis, uint96 harga, string teks, uint40 dibuatPada
    );
    /// @notice Rincian order v2, dipancarkan tepat setelah OrderCreated.
    event OrderDetail(uint64 indexed id, uint16 halaman, uint32 batasKerja, bytes32 dokumen, bytes32 kodeHash);
    event OrderRelayed(uint64 indexed id, address indexed relayer, uint256 fee);
    event OrderClaimed(uint64 indexed id, address indexed toko, uint40 diclaimPada);
    event StepCompleted(uint64 indexed id, address indexed toko, uint8 urutan, uint8 kode);
    event OrderReady(uint64 indexed id, address indexed toko, uint32 kerja, uint256 payout, uint40 siapPada);
    /// @param diserahkan true bila lewat QR pelanggan (atau order tanpa kode); false bila ditutup setelah batasJemput
    event OrderFinished(uint64 indexed id, address indexed toko, uint256 payout, uint256 refund, uint32 kerja, bool diserahkan);
    event OrderExpired(uint64 indexed id, uint256 refund, AlasanExpire alasan);
    event OrderDisputed(uint64 indexed id);
    /// @param otomatis true bila ditutup setelah batasSengketa tanpa keputusan operator (bagian default)
    event DisputeResolved(uint64 indexed id, address indexed toko, uint256 payout, uint256 refund, bool otomatis);

    // --------------------------------------------------------------- error

    error NotOperator();
    error NotShop();
    error NotYourOrder();
    error SessionClosed();
    error SessionOpen();
    error BadKind();
    error BadRecipe();
    error BadValue();
    error BadText();
    error ShopExists();
    error TooManyShops();
    error AlreadyClaimed();
    error ShopBusy();
    error QueueTimeout();
    error NotClaimed();
    error WrongStep();
    error Late();
    error NotExpired();
    error SignatureExpired();
    error BadSignature();
    error FeeTooHigh();
    error BadPages();
    error NotReady();
    error BadCode();
    error NotCustomer();
    error TooLate();
    error NotDisputed();
    error BadShare();

    // ----------------------------------------------------------- modifier

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    constructor(
        string memory nama_,
        string memory simbol_,
        uint32 batasAntre_,
        uint32 batasJemput_,
        uint32 batasSengketa_,
        IERC20 token_
    )
        ERC721(nama_, simbol_)
        EIP712("FotokopiKilat", "2")
    {
        if (batasAntre_ == 0 || batasJemput_ == 0 || batasSengketa_ == 0 || address(token_) == address(0)) revert BadValue();
        operator = msg.sender;
        batasAntre = batasAntre_;
        batasJemput = batasJemput_;
        batasSengketa = batasSengketa_;
        token = token_;
    }

    // --------------------------------------------------------------- admin

    /// @param langkah kode langkah berurutan, tiap kode 1..LANGKAH_TERTINGGI
    function setKatalog(
        uint8 jenis,
        uint96 hargaDasar,
        uint96 hargaPerHalaman,
        uint32 batasDasar,
        uint32 batasPerHalaman,
        uint8[] calldata langkah,
        string calldata label
    ) external onlyOperator {
        if (jenis == 0) revert BadKind();
        if (uint256(hargaDasar) + hargaPerHalaman == 0 || uint256(batasDasar) + batasPerHalaman == 0) revert BadValue();
        // order terbesar (MAX_HALAMAN) harus muat di uint96 / uint32
        if (uint256(hargaDasar) + uint256(hargaPerHalaman) * MAX_HALAMAN > type(uint96).max) revert BadValue();
        if (uint256(batasDasar) + uint256(batasPerHalaman) * MAX_HALAMAN > type(uint32).max) revert BadValue();
        uint256 n = langkah.length;
        if (n == 0 || n > MAX_LANGKAH) revert BadRecipe();
        if (!_teksValid(bytes(label))) revert BadText();

        uint32 packed = 0;
        for (uint256 i; i < n; ++i) {
            uint8 kode = langkah[i];
            if (kode == 0 || kode > LANGKAH_TERTINGGI) revert BadRecipe();
            packed |= uint32(kode) << uint32(8 * (3 - i));
        }
        katalog[jenis] =
            Katalog(hargaDasar, hargaPerHalaman, batasDasar, batasPerHalaman, bytes4(packed), uint8(n), true, label);
        emit KatalogSet(jenis, hargaDasar, hargaPerHalaman, batasDasar, batasPerHalaman, bytes4(packed), uint8(n), label);
    }

    function setFeeRelay(uint96 fee) external onlyOperator {
        feeRelay = fee;
        emit FeeRelaySet(fee);
    }

    /// @notice Atur revenue platform: potongan dari payout toko (maks. 10%), treasury penerima, harga Toko Pro per 30 hari.
    function setPlatform(uint16 feeBps, address treasury_, uint96 hargaPro_) external onlyOperator {
        if (feeBps > MAX_PLATFORM_FEE_BPS) revert BadShare();
        if (treasury_ == address(0)) revert BadValue();
        platformFeeBps = feeBps;
        treasury = treasury_;
        hargaPro = hargaPro_;
        emit PlatformSet(feeBps, treasury_, hargaPro_);
    }

    function registerShop(address alamat, string calldata nama) external onlyOperator {
        if (toko[alamat].terdaftar) revert ShopExists();
        if (daftarToko.length >= MAX_TOKO) revert TooManyShops();
        if (!_teksValid(bytes(nama))) revert BadText();
        toko[alamat] = Toko(true, 0, nama);
        daftarToko.push(alamat);
        emit ShopRegistered(alamat, nama);
    }

    function startSession() external onlyOperator {
        if (sesiAktif) revert SessionOpen();
        sesiAktif = true;
        uint32 id = ++sesiId;
        emit SessionStarted(id, uint40(block.timestamp));
    }

    function endSession() external onlyOperator {
        if (!sesiAktif) revert SessionClosed();
        sesiAktif = false;
        emit SessionEnded(sesiId, uint40(block.timestamp));
    }

    // ----------------------------------------------------------- pelanggan

    /// @notice Pesan langsung (pelanggan membayar gas sendiri dan sudah `approve` token ke contract).
    /// @param dokumen hash dokumen terenkripsi (0 = tanpa dokumen) · @param kodeHash keccak256(rahasia QR) (0 = tanpa serah terima)
    function createOrder(uint8 jenis, string calldata teks, uint16 halaman, bytes32 dokumen, bytes32 kodeHash)
        external
        nonReentrant
        returns (uint64 id)
    {
        (uint96 harga, uint32 batas) = _cekPesanan(jenis, teks, halaman);
        token.safeTransferFrom(msg.sender, address(this), harga);
        id = _buatOrder(msg.sender, jenis, teks, harga, batas);
        _simpanDetail(id, halaman, batas, dokumen, kodeHash);
    }

    /// @notice Pesan atas nama pelanggan tanpa MON: pelanggan menandatangani `Pesanan` (EIP-712) dan `permit` token;
    /// relayer (msg.sender) membayar gas dan menerima `feeRelay` dari token pelanggan.
    function createOrderFor(Pesanan calldata p, bytes calldata sig, Izin calldata izin)
        external
        nonReentrant
        returns (uint64 id)
    {
        if (block.timestamp > p.deadline) revert SignatureExpired();
        uint96 fee = feeRelay;
        if (fee > p.maxFee) revert FeeTooHigh();
        (uint96 harga, uint32 batas) = _cekPesanan(p.jenis, p.teks, p.halaman);
        if (ECDSA.recover(_digestPesanan(p, nonces[p.pelanggan]++), sig) != p.pelanggan) revert BadSignature();

        // permit bisa sudah dipakai (front-run) — allowance tetap dicek oleh transferFrom di bawah
        if (izin.deadline != 0) {
            try IERC20Permit(address(token)).permit(p.pelanggan, address(this), izin.value, izin.deadline, izin.v, izin.r, izin.s) {} catch {}
        }
        // `from` = pelanggan yang tanda tangannya baru diverifikasi di atas (bukan alamat sembarang).
        // forge-lint: disable-next-line(arbitrary-send-erc20)
        token.safeTransferFrom(p.pelanggan, address(this), harga);
        // forge-lint: disable-next-line(arbitrary-send-erc20)
        if (fee != 0) token.safeTransferFrom(p.pelanggan, msg.sender, fee);

        id = _buatOrder(p.pelanggan, p.jenis, p.teks, harga, batas);
        _simpanDetail(id, p.halaman, batas, p.dokumen, p.kodeHash);
        emit OrderRelayed(id, msg.sender, fee);
    }

    /// @notice Pelanggan menolak hasil saat order Siap (sebelum batasJemput): dana ditahan sampai operator memutuskan.
    function komplain(uint64 id) external {
        Order storage o = order[id];
        if (o.status != Status.Siap) revert NotReady();
        if (msg.sender != o.pelanggan) revert NotCustomer();
        if (block.timestamp >= uint256(o.siapPada) + batasJemput) revert TooLate();
        o.status = Status.Sengketa;
        emit OrderDisputed(id);
    }

    // ---------------------------------------------------------------- toko

    function claim(uint64 id) external {
        Toko storage t = toko[msg.sender];
        if (!t.terdaftar) revert NotShop();
        if (!sesiAktif) revert SessionClosed();
        Order storage o = order[id];
        if (o.status != Status.Open) revert AlreadyClaimed();
        if (t.orderAktif != 0) revert ShopBusy();
        if (block.timestamp >= uint256(o.dibuatPada) + batasAntre) revert QueueTimeout();

        o.status = Status.Claimed;
        o.toko = msg.sender;
        o.diclaimPada = uint40(block.timestamp);
        t.orderAktif = id;
        emit OrderClaimed(id, msg.sender, uint40(block.timestamp));
    }

    function completeStep(uint64 id, uint8 kode) external nonReentrant {
        Order storage o = order[id];
        if (o.status != Status.Claimed) revert NotClaimed();
        if (o.toko != msg.sender) revert NotYourOrder();
        uint8 urutan = o.langkahSelesai;
        if (kode != uint8(o.langkah[urutan])) revert WrongStep();
        uint256 kerja = block.timestamp - o.diclaimPada;
        if (kerja >= o.batasKerja) revert Late();

        o.langkahSelesai = urutan + 1;
        emit StepCompleted(id, msg.sender, urutan, kode);
        if (urutan + 1 != o.jumlahLangkah) return;

        // Langkah terakhir: waktu kerja dan payout terkunci; toko bebas mengambil order lain.
        o.kerja = uint32(kerja);
        toko[msg.sender].orderAktif = 0;
        if (o.kodeHash == bytes32(0)) {
            _selesaikan(id, o, true);
        } else {
            o.status = Status.Siap;
            o.siapPada = uint40(block.timestamp);
            emit OrderReady(id, msg.sender, uint32(kerja), _payout(o.harga, o.batasKerja, kerja), uint40(block.timestamp));
        }
    }

    /// @notice Serah terima: toko memindai QR pelanggan berisi `rahasia`; dana cair dan NFT dicetak.
    function serahkan(uint64 id, bytes32 rahasia) external nonReentrant {
        Order storage o = order[id];
        if (o.status != Status.Siap) revert NotReady();
        if (o.toko != msg.sender) revert NotYourOrder();
        if (keccak256(abi.encodePacked(rahasia)) != o.kodeHash) revert BadCode();
        _selesaikan(id, o, true);
    }

    /// @notice Langganan Toko Pro `periode` × 30 hari, dibayar dari saldo token toko ke treasury (perlu `approve`).
    /// Manfaat Pro di luar contract (radius feed lebih luas, badge, statistik); rebutan claim tetap setara.
    function langgananPro(uint8 periode) external nonReentrant {
        if (!toko[msg.sender].terdaftar) revert NotShop();
        if (periode == 0 || periode > MAX_PERIODE_PRO || hargaPro == 0) revert BadValue();
        uint256 mulai = proSampai[msg.sender] > block.timestamp ? proSampai[msg.sender] : block.timestamp;
        uint40 sampai = uint40(mulai + uint256(periode) * PERIODE_PRO);
        uint256 bayar = uint256(hargaPro) * periode;
        proSampai[msg.sender] = sampai;
        emit ProSubscribed(msg.sender, sampai, bayar);
        token.safeTransferFrom(msg.sender, treasury, bayar);
    }

    // ------------------------------------------------------------- operator

    /// @notice Putuskan sengketa: toko menerima `bagianToko` (basis poin) dari payout yang terkunci saat Siap,
    /// sisanya kembali ke pelanggan. Order sengketa tidak mendapat NFT.
    function putuskan(uint64 id, uint16 bagianToko) external onlyOperator nonReentrant {
        Order storage o = order[id];
        if (o.status != Status.Sengketa) revert NotDisputed();
        if (bagianToko > BPS) revert BadShare();
        _putuskan(id, o, bagianToko, false);
    }

    // --------------------------------------------------------- siapa saja

    /// @notice Sengketa yang tidak diputuskan operator sampai siapPada + batasJemput + batasSengketa ditutup siapa saja
    /// (keeper) dengan bagian default, supaya dana tidak tertahan selamanya bila operator tidak bertindak.
    function tutupSengketa(uint64 id) external nonReentrant {
        Order storage o = order[id];
        if (o.status != Status.Sengketa) revert NotDisputed();
        if (block.timestamp < uint256(o.siapPada) + batasJemput + batasSengketa) revert NotExpired();
        _putuskan(id, o, BAGIAN_DEFAULT_SENGKETA, true);
    }

    function _putuskan(uint64 id, Order storage o, uint16 bagianToko, bool otomatis) private {
        uint256 harga = o.harga;
        uint256 payout = _payout(harga, o.batasKerja, o.kerja) * bagianToko / BPS;
        uint256 refund = harga - payout;
        uint256 fee = payout * platformFeeBps / BPS;
        address t = o.toko;
        o.status = Status.Diputuskan;
        omzet[o.sesi][t] += payout - fee;
        emit DisputeResolved(id, t, payout - fee, refund, otomatis);
        _bayar(id, t, payout - fee, fee, o.pelanggan, refund);
    }

    /// @notice Dipanggil keeper/siapa saja. Open lewat batas antre atau Claimed lewat batas kerja: refund penuh.
    /// Siap lewat batasJemput: ditutup tanpa serah terima (toko tetap dibayar karena pekerjaan sudah siap).
    function expire(uint64 id) external nonReentrant {
        Order storage o = order[id];
        AlasanExpire alasan;
        if (o.status == Status.Siap) {
            if (block.timestamp < uint256(o.siapPada) + batasJemput) revert NotExpired();
            _selesaikan(id, o, false);
            return;
        }
        if (o.status == Status.Open) {
            if (block.timestamp < uint256(o.dibuatPada) + batasAntre) revert NotExpired();
            alasan = AlasanExpire.Antre;
        } else if (o.status == Status.Claimed) {
            if (block.timestamp < uint256(o.diclaimPada) + o.batasKerja) revert NotExpired();
            alasan = AlasanExpire.Kerja;
            toko[o.toko].orderAktif = 0;
        } else {
            revert NotExpired();
        }
        o.status = Status.Expired;
        uint256 refund = o.harga;
        emit OrderExpired(id, refund, alasan);
        token.safeTransfer(o.pelanggan, refund);
    }

    // --------------------------------------------------------------- view

    /// @notice Order lengkap sebagai struct (getter publik `order` mengembalikan 14 nilai terpisah).
    function getOrder(uint64 id) external view returns (Order memory) {
        return order[id];
    }

    function jumlahToko() external view returns (uint256) {
        return daftarToko.length;
    }

    /// @notice Domain separator EIP-712, untuk FE/relayer yang menyusun tanda tangan `Pesanan`.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Toko dengan omzet tertinggi di sesi; seri dimenangkan toko yang terdaftar lebih dulu.
    function pemenang(uint32 sesi) external view returns (address terbaik, uint256 omzetTerbaik) {
        uint256 n = daftarToko.length;
        for (uint256 i; i < n; ++i) {
            address a = daftarToko[i];
            uint256 v = omzet[sesi][a];
            if (v > omzetTerbaik) (terbaik, omzetTerbaik) = (a, v);
        }
    }

    function isPro(address t) external view returns (bool) {
        return proSampai[t] > block.timestamp;
    }

    /// @notice Harga dan batas kerja untuk `halaman` halaman jenis ini (sama dengan yang ditarik saat memesan).
    function hargaUntuk(uint8 jenis, uint16 halaman) external view returns (uint96 harga, uint32 batasKerja) {
        return _hitung(katalog[jenis], halaman);
    }

    /// @notice Kode langkah ke-`urutan` dari resep katalog.
    function langkahKatalog(uint8 jenis, uint8 urutan) external view returns (uint8) {
        return uint8(katalog[jenis].langkah[urutan]);
    }

    /// @notice Payout bila langkah terakhir selesai sekarang (0 bila sudah lewat batas); untuk order Siap/Sengketa
    /// mengembalikan payout yang sudah terkunci. Dipakai FE untuk cek.
    function payoutSekarang(uint64 id) external view returns (uint256) {
        Order storage o = order[id];
        if (o.status == Status.Siap || o.status == Status.Sengketa) return _payout(o.harga, o.batasKerja, o.kerja);
        if (o.status != Status.Claimed) return 0;
        uint256 kerja = block.timestamp - o.diclaimPada;
        if (kerja >= o.batasKerja) return 0;
        return _payout(o.harga, o.batasKerja, kerja);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        Order storage o = order[uint64(tokenId)];
        string memory label = katalog[o.jenis].label;
        string memory json = string.concat(
            '{"name":"',
            label,
            " #",
            tokenId.toString(),
            '","description":"Hasil cetakan dari ',
            toko[o.toko].nama,
            '","attributes":[{"trait_type":"Toko","value":"',
            toko[o.toko].nama,
            '"},{"trait_type":"Halaman","display_type":"number","value":',
            uint256(o.halaman).toString(),
            '},{"trait_type":"Waktu kerja (dtk)","display_type":"number","value":',
            uint256(o.kerja).toString(),
            '}],"image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(_svg(tokenId, o, label))),
            '"}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    // ------------------------------------------------------------ internal

    function _cekPesanan(uint8 jenis, string calldata teks, uint16 halaman)
        private
        view
        returns (uint96 harga, uint32 batas)
    {
        if (!sesiAktif) revert SessionClosed();
        Katalog storage k = katalog[jenis];
        if (!k.aktif) revert BadKind();
        if (!_teksValid(bytes(teks))) revert BadText();
        if (halaman == 0 || halaman > MAX_HALAMAN) revert BadPages();
        (harga, batas) = _hitung(k, halaman);
    }

    function _hitung(Katalog storage k, uint16 halaman) private view returns (uint96, uint32) {
        // setKatalog menjamin hasilnya muat untuk halaman <= MAX_HALAMAN
        return (
            uint96(uint256(k.hargaDasar) + uint256(k.hargaPerHalaman) * halaman),
            uint32(uint256(k.batasDasar) + uint256(k.batasPerHalaman) * halaman)
        );
    }

    function _digestPesanan(Pesanan calldata p, uint256 nonce) private view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    PESANAN_TYPEHASH,
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
            )
        );
    }

    function _simpanDetail(uint64 id, uint16 halaman, uint32 batas, bytes32 dokumen, bytes32 kodeHash) private {
        Order storage o = order[id];
        o.halaman = halaman;
        if (dokumen != bytes32(0)) o.dokumen = dokumen;
        if (kodeHash != bytes32(0)) o.kodeHash = kodeHash;
        emit OrderDetail(id, halaman, batas, dokumen, kodeHash);
    }

    function _buatOrder(address pelanggan, uint8 jenis, string calldata teks, uint96 harga, uint32 batas)
        private
        returns (uint64 id)
    {
        Katalog storage k = katalog[jenis];
        id = nextId++;
        Order storage o = order[id];
        o.pelanggan = pelanggan;
        o.harga = harga;
        o.jenis = jenis;
        o.langkah = k.langkah;
        o.jumlahLangkah = k.jumlahLangkah;
        o.status = Status.Open;
        o.dibuatPada = uint40(block.timestamp);
        o.batasKerja = batas;
        o.sesi = sesiId;
        o.teks = teks;
        emit OrderCreated(id, pelanggan, jenis, harga, teks, uint40(block.timestamp));
    }

    /// @dev Dipanggil saat langkah terakhir (tanpa kode), serah terima, atau batasJemput lewat. `o.kerja` sudah terkunci.
    function _selesaikan(uint64 id, Order storage o, bool diserahkan) private {
        uint256 harga = o.harga;
        uint32 kerja = o.kerja;
        uint256 payout = _payout(harga, o.batasKerja, kerja);
        uint256 refund = harga - payout;
        uint256 fee = payout * platformFeeBps / BPS;
        address t = o.toko;
        address p = o.pelanggan;

        o.status = Status.Finished;
        omzet[o.sesi][t] += payout - fee;
        _mint(p, id);
        emit OrderFinished(id, t, payout - fee, refund, kerja, diserahkan);
        _bayar(id, t, payout - fee, fee, p, refund);
    }

    /// @dev Bayar toko (bersih), fee platform ke treasury, sisa ke pelanggan. Dipanggil setelah semua state ditulis.
    /// Transfer ERC-20 tidak menjalankan kode penerima, jadi penerima tidak bisa memblokir order.
    function _bayar(uint64 id, address t, uint256 bersih, uint256 fee, address p, uint256 refund) private {
        if (fee != 0) {
            emit PlatformFeeTaken(id, fee);
            token.safeTransfer(treasury, fee);
        }
        if (bersih != 0) token.safeTransfer(t, bersih);
        if (refund != 0) token.safeTransfer(p, refund);
    }

    function _payout(uint256 harga, uint256 batasKerja, uint256 kerja) private pure returns (uint256) {
        return harga * (batasKerja - kerja) / batasKerja;
    }

    /// @dev 1..MAX_TEXT byte, ASCII cetak 0x20..0x7E, tanpa < > & " ' (aman untuk SVG dan JSON).
    /// Backslash juga ditolak supaya JSON metadata tidak rusak.
    function _teksValid(bytes memory b) private pure returns (bool) {
        uint256 n = b.length;
        if (n == 0 || n > MAX_TEXT) return false;
        for (uint256 i; i < n; ++i) {
            bytes1 c = b[i];
            if (c < 0x20 || c > 0x7e) return false;
            if (c == "<" || c == ">" || c == "&" || c == '"' || c == "'" || c == "\\") return false;
        }
        return true;
    }

    function _svg(uint256 tokenId, Order storage o, string memory label) private view returns (string memory) {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400" font-family="monospace">',
            '<rect width="400" height="400" rx="18" fill="#141516"/>',
            '<rect x="10" y="10" width="380" height="380" rx="12" fill="none" stroke="#3a3b3d"/>',
            _kertas(o.teks),
            _caption(tokenId, o, label),
            "</svg>"
        );
    }

    /// @dev Selembar kertas isometrik (bidang atas, sudut 30 derajat) dengan teks di permukaannya.
    function _kertas(string storage teks) private pure returns (string memory) {
        return string.concat(
            '<g transform="matrix(0.866 0.5 -0.866 0.5 200 92)">',
            '<rect x="6" y="6" width="190" height="150" rx="4" fill="#0c0d0e"/>',
            '<rect width="190" height="150" rx="4" fill="#f6f6f5" stroke="#836ef9" stroke-width="1.5"/>',
            '<path d="M16 26h120M16 40h150M16 54h96" stroke="#c9c9c6" stroke-width="3"/>',
            '<text x="16" y="96" font-size="12" fill="#141516">',
            teks,
            "</text></g>"
        );
    }

    function _caption(uint256 tokenId, Order storage o, string memory label) private view returns (string memory) {
        return string.concat(
            '<text x="26" y="40" font-size="12" fill="#8a8b8d">Fig ',
            tokenId.toString(),
            '</text><text x="374" y="40" font-size="12" fill="#e9eaea" text-anchor="end" letter-spacing="1.5">',
            label,
            '</text><text x="26" y="372" font-size="12" fill="#8a8b8d">',
            toko[o.toko].nama,
            '</text><text x="374" y="372" font-size="12" fill="#836ef9" text-anchor="end">',
            uint256(o.kerja).toString(),
            " dtk</text>"
        );
    }
}
