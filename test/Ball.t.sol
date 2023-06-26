pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { UniSetUp, PoolArgs, Asset } from "../test/UniHelper.sol";

import { Ball } from '../src/ball.sol';
import { INonfungiblePositionManager } from './Univ3Interface.sol';
import { Gem, GemFab } from '../lib/gemfab/src/gem.sol';
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { Divider } from '../lib/feedbase/src/combinators/Divider.sol';
import { Medianizer } from '../lib/feedbase/src/Medianizer.sol';
import { UniswapV3Adapter } from "../lib/feedbase/src/adapters/UniswapV3Adapter.sol";
import { Vat } from '../src/vat.sol';
import { Math } from '../src/mixin/math.sol';
import { WethLike } from '../test/RicoHelper.sol';
import {ChainlinkAdapter} from "../lib/feedbase/src/adapters/ChainlinkAdapter.sol";
import {TWAP} from "../lib/feedbase/src/combinators/TWAP.sol";
import {Progression} from "../lib/feedbase/src/combinators/Progression.sol";
import { Vow } from "../src/vow.sol";
import { ERC20Hook } from '../src/hook/ERC20hook.sol';
import { Vox } from "../src/vox.sol";
import { Bank } from '../src/bank.sol';
import { File } from '../src/file.sol';
import { BankDiamond } from '../src/diamond.sol';
import {Ploker} from '../src/test/Ploker.sol';

contract BallTest is Test, UniSetUp, Math {
    bytes32 internal constant WILK = "weth";
    uint8   public immutable EXACT_IN  = 0;
    uint8   public immutable EXACT_OUT = 1;
    address internal constant DAI   = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant WETH  = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WETH_USD_AGG  = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    bytes32 internal constant WETH_ILK = "weth";
    bytes32 internal constant WETH_DAI_TAG = "weth:dai";
    bytes32 internal constant WETH_RICO_TAG = "weth:rico";
    bytes32 internal constant WETH_USD_TAG = "weth:usd";
    bytes32 internal constant RICO_DAI_TAG = "rico:dai";
    bytes32 internal constant DAI_RICO_TAG = "dai:rico";
    bytes32 internal constant XAU_USD_TAG = "xau:usd";
    bytes32 internal constant DAI_USD_TAG = "dai:usd";
    bytes32 internal constant RICO_XAU_TAG = "rico:xau";
    bytes32 internal constant REF_RICO_TAG = "ref:rico";
    bytes32 internal constant RICO_REF_TAG = "rico:ref";
    bytes32 constant public RICO_RISK_TAG  = "rico:risk";
    bytes32 constant public RISK_RICO_TAG  = "risk:rico";
    Ploker ploker;
    ChainlinkAdapter cladapt;
    UniswapV3Adapter uniadapt;
    Divider divider;
    Medianizer mdn;
    Feedbase fb;
    GemFab gf;
    address payable bank;
    address me;
    INonfungiblePositionManager npfm = INonfungiblePositionManager(
        0xC36442b4a4522E871399CD717aBDD847Ab11FE88
    );
    address COMPOUND_CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    uint256 constant public BANKYEAR = (365 * 24 + 6) * 3600;
    address rico;
    address risk;
    address ricodai;
    address ricorisk;
    uint24  constant public RICO_FEE = 500;
    uint24  constant public RISK_FEE = 3000;
    uint160 constant public risk_price = 2 ** 96;
    uint256 constant INIT_SQRTPAR = RAY * 2;
    uint256 constant INIT_PAR = (INIT_SQRTPAR ** 2) / RAY;
    uint256 constant wethricoprice = 1500 * RAY * RAY / INIT_PAR;
    uint256 constant wethamt = WAD;
    int256  constant dart = int(wethamt * wethricoprice / INIT_PAR);
    bytes32[] ilks;
    uint DEV_FUND_RISK = 1000000 * WAD;
    uint DUST = 90 * RAD;

    ERC20Hook hook;
    Vat vat;
    Vow vow;
    Vox vox;

    receive () payable external {}

    function advance_chainlink() internal {
        // chainlink adapter advances from chainlink time
        // a ploke will overwrite this back to chain time
        vm.startPrank(address(cladapt));
        (bytes32 v,) = fb.pull(address(cladapt), XAU_USD_TAG);
        fb.push(XAU_USD_TAG,  v, block.timestamp + 100_000);
        (v,) = fb.pull(address(cladapt), DAI_USD_TAG);
        fb.push(DAI_USD_TAG,  v, block.timestamp + 100_000);
        (v,) = fb.pull(address(cladapt), WETH_USD_TAG);
        fb.push(WETH_USD_TAG, v, block.timestamp + 100_000);
        vm.stopPrank();
    }

    function advance_uni() internal {
        // uni adapter advances from chainlink time
        vm.startPrank(address(uniadapt));
        (bytes32 v,) = fb.pull(address(uniadapt), RICO_DAI_TAG);
        fb.push(RICO_DAI_TAG,  v, block.timestamp + 100_000);
        (v,) = fb.pull(address(uniadapt), RICO_RISK_TAG);
        fb.push(RICO_RISK_TAG, v, block.timestamp + 100_000);
        vm.stopPrank();
    }

    function _ink(bytes32 ilk, address usr) internal returns (uint) {
        return abi.decode(Vat(bank).ink(ilk, usr), (uint));
    }

    function look_poke() internal {
        ploker.ploke(RICO_RISK_TAG);
        ploker.ploke(RISK_RICO_TAG);

        cladapt.look(WETH_USD_TAG);
        cladapt.look(DAI_USD_TAG);
        cladapt.look(XAU_USD_TAG);
        uniadapt.look(RICO_DAI_TAG);
        advance_chainlink();
        advance_uni();

        mdn.poke(WETH_RICO_TAG);
        mdn.poke(RICO_REF_TAG);
    }

    function make_uniwrapper() internal returns (address deployed) {
        bytes memory args = abi.encode('');
        bytes memory bytecode = abi.encodePacked(vm.getCode(
            "../lib/feedbase/artifacts/src/adapters/UniWrapper.sol:UniWrapper"
        ), args);
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }

    function make_diamond() internal returns (address payable deployed) {
        return payable(address(new BankDiamond()));
    }

    function setUp() public {
        me = address(this);
        gf = new GemFab();
        fb = new Feedbase();
        rico = address(gf.build(bytes32("Rico"), bytes32("RICO")));
        risk = address(gf.build(bytes32("Rico Riskshare"), bytes32("RISK")));
        uint160 sqrtparx96 = uint160(INIT_SQRTPAR * (2 ** 96) / RAY);
        ricodai = create_pool(rico, DAI, 500, sqrtparx96);
        ricorisk = create_pool(rico, risk, RISK_FEE, risk_price);

        Ball.IlkParams[] memory ips = new Ball.IlkParams[](1);
        ilks = new bytes32[](1);
        ilks[0] = WETH_ILK;
        assertEq(ilks.length, 1);
        ips[0] = Ball.IlkParams(
            'weth',
            WETH,
            WETH_USD_AGG,
            RAY, // chop
            DUST, // dust
            1000000001546067052200000000, // fee
            100000 * RAD, // line
            RAY, // liqr
            20000, // ttl
            1 // range
        );

        address uniwrapper = make_uniwrapper();
        bank = make_diamond();
        Ball.UniParams memory ups = Ball.UniParams(
            0xC36442b4a4522E871399CD717aBDD847Ab11FE88,
            ':uninft',
            1000000001546067052200000000,
            RAY,
            8,
            uniwrapper
        );

        Ball.BallArgs memory bargs = Ball.BallArgs(
            bank,
            address(fb),
            rico,
            risk,
            ricodai,
            ricorisk,
            router,
            uniwrapper,
            INIT_PAR,
            100000 * WAD,
            20000, // ricodai
            BANKYEAR * 100,
            BANKYEAR, // daiusd
            BANKYEAR, // xauusd
            RAY,  // flappep
            RAY,  // flappop
            RAY,  // floppep
            RAY,  // floppop
            Bank.Ramp(WAD, WAD, block.timestamp, 1),
            0x6B175474E89094C44Da98b954EedeAC495271d0F,
            0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9,
            0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6
        );

        uint gas = gasleft();
        Ball ball = new Ball(bargs);
        BankDiamond(bank).transferOwnership(address(ball));
        ball.setup(bargs);
        ball.makeilk(ips[0]);
        ball.makeuni(ups);
        ball.approve(me);
        BankDiamond(bank).acceptOwnership();

        uint usedgas     = gas - gasleft();
        uint expectedgas = 23633732;
        if (usedgas < expectedgas) {
            console.log("ball saved %s gas...currently %s", expectedgas - usedgas, usedgas);
        }
        if (usedgas > expectedgas) {
            console.log("ball gas increase by %s...currently %s", usedgas - expectedgas, usedgas);
        }

        Gem(rico).ward(bank, true);
        Gem(risk).ward(bank, true);

        vat = ball.vat();
        cladapt = ball.cladapt();
        uniadapt = ball.uniadapt();
        divider = ball.divider();
        mdn = ball.mdn();
        ploker = ball.ploker();
        skip(40000);
        cladapt.look(XAU_USD_TAG);
        cladapt.look(DAI_USD_TAG);
        cladapt.look(WETH_USD_TAG);
        uniadapt.look(RICO_DAI_TAG);
        uniadapt.look(RICO_RISK_TAG);
        look_poke();
        skip(BANKYEAR / 2);

        hook = ball.hook();
        vm.prank(VAULT);
        Gem(DAI).transfer(address(this), 500 * WAD);
        Gem(WETH).approve(bank, type(uint).max);
        WethLike(WETH).deposit{value: wethamt * 100}();

        cladapt.look(XAU_USD_TAG);
        cladapt.look(DAI_USD_TAG);

        look_poke();

        vow = ball.vow();
        vox = ball.vox();

        Gem(risk).mint(address(this), DEV_FUND_RISK);
        Gem(rico).approve(bank, type(uint256).max);
        Gem(risk).approve(bank, type(uint256).max);
    }

    modifier _flap_after_ {
        _;
        uint vow_risk_before = Gem(risk).balanceOf(bank);
        Gem(risk).mint(me, 10000 * WAD);
        Vow(bank).keep(ilks);
        uint vow_risk_after = Gem(risk).balanceOf(bank);
        assertGt(vow_risk_after, vow_risk_before);
    }

    modifier _flop_after_ {
        _;
        vm.expectCall(risk, abi.encodePacked(Gem(risk).mint.selector));
        Vow(bank).keep(ilks);
    }

    modifier _balanced_after_ {
        _;
        // should not be any auctions
        uint me_risk_1 = Gem(risk).balanceOf(me);
        uint me_rico_1 = Gem(rico).balanceOf(me);

        Vow(bank).keep(ilks);

        uint me_risk_2 = Gem(risk).balanceOf(me);
        uint me_rico_2 = Gem(rico).balanceOf(me);

        assertEq(me_risk_1, me_risk_2);
        assertEq(me_rico_1, me_rico_2);
    }

    function test_basic() public {
        ploker.ploke(RICO_REF_TAG);
        (bytes32 price, uint ttl) = fb.pull(address(mdn), RICO_REF_TAG);
        uint vox_price = rmul(uint(price), Vox(bank).amp());
        assertGt(uint(vox_price), INIT_PAR * 99 / 100);
        assertLt(uint(vox_price), INIT_PAR * 100 / 99);
        (price, ttl) = fb.pull(address(mdn), WETH_RICO_TAG);
        // ether price about 1600 rn
        assertGt(uint(price) / RAY, 1000 * RAY / INIT_PAR);
        assertLt(uint(price) / RAY, 2000 * RAY / INIT_PAR);
    }

    function test_ball_1() public {
        Vat(bank).frob(WETH_ILK, me, abi.encodePacked(wethamt), dart);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(WETH_ILK, me, abi.encodePacked(int(0)), dart);
    }

    function test_fee_bail_flop() public _flop_after_ {
        Vat(bank).frob(WETH_ILK, me, abi.encodePacked(wethamt), dart);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        Vow(bank).bail(WETH_ILK, me);
        skip(BANKYEAR * 100);
        // revert bc feed data old
        vm.expectRevert(Vow.ErrSafeBail.selector);
        Vow(bank).bail(WETH_ILK, me);
        look_poke();
        Vow(bank).keep(ilks);
        uint meweth = WethLike(WETH).balanceOf(me);
        Gem(rico).mint(me, 1000000 * WAD);
        Vow(bank).bail(WETH_ILK, me);
        assertGt(WethLike(WETH).balanceOf(me), meweth);
    }


    function test_ball_flap() public _flap_after_ {
        Vat(bank).frob(WETH_ILK, me, abi.encodePacked(wethamt), dart);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        Vow(bank).bail(WETH_ILK, me);
        skip(BANKYEAR * 100);
    }

    // user pays down the urn first, then try to flap
    function test_ball_pay_flap_1() public {
        Vat(bank).frob(WETH_ILK, me, abi.encodePacked(wethamt), dart);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        Vow(bank).bail(WETH_ILK, me);
        skip(BANKYEAR * 100); advance_chainlink(); look_poke();

        uint artleft = Vat(bank).urns(WETH_ILK, me);
        uint inkleft = _ink(WETH_ILK, me);

        uint rack = Vat(bank).ilks(WETH_ILK).rack;
        uint dust = Vat(bank).ilks(WETH_ILK).dust;
        Vat(bank).frob(WETH_ILK, me, abi.encodePacked(int(0)), -int((artleft * rack - dust) / rack));
        uint artleftafter = Vat(bank).urns(WETH_ILK, me);
        uint inkleftafter = _ink(WETH_ILK, me);
        assertEq(inkleftafter, inkleft);
        assertEq(artleftafter, dust / rack);

        uint self_risk_1 = Gem(risk).balanceOf(me);
        Vow(bank).keep(ilks);
        uint self_risk_2 = Gem(risk).balanceOf(me);
        assertLt(self_risk_2, self_risk_1);
    }

    function test_ball_pay_flap_success() public  _balanced_after_ {
        Vat(bank).frob(WETH_ILK, me, abi.encodePacked(wethamt), dart);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        Vow(bank).bail(WETH_ILK, me);
        skip(BANKYEAR * 100); look_poke();

        uint artleft = Vat(bank).urns(WETH_ILK, me);
        uint inkleft = _ink(WETH_ILK, me);
        Vow(bank).keep(ilks); // drips
        Gem(rico).mint(me, artleft * 1000);
        uint rack = Vat(bank).ilks(WETH_ILK).rack;
        uint dust = Vat(bank).ilks(WETH_ILK).dust;
        Vat(bank).frob(WETH_ILK, me, abi.encodePacked(int(0)), -int((artleft * rack - dust) / rack));
        uint artleftafter = Vat(bank).urns(WETH_ILK, me);
        uint inkleftafter = _ink(WETH_ILK, me);
        assertEq(inkleftafter, inkleft);
        assertGt(artleftafter, dust / rack * 999 / 1000);
        assertLt(artleftafter, dust / rack * 1000 / 999);
        // balanced now because already kept
    }

    function test_ward() public {
        vm.prank(VAULT);
        vm.expectRevert(abi.encodeWithSelector(
            Bank.ErrWard.selector, VAULT, bank, File.file.selector
        ));
        File(bank).file('ceil', bytes32(WAD));
        File(bank).ward(VAULT, true);
        vm.prank(VAULT);
        File(bank).file('ceil', bytes32(WAD));
        File(bank).ward(VAULT, false);
        File(bank).file('ceil', bytes32(WAD));


        vm.prank(VAULT);
        vm.expectRevert(abi.encodeWithSelector(
            Bank.ErrWard.selector, VAULT, bank, File.file.selector
        ));
        File(bank).file('ceil', bytes32(WAD));


        BankDiamond(bank).transferOwnership(VAULT);
        vm.prank(VAULT);
        BankDiamond(bank).acceptOwnership();

        vm.expectRevert(abi.encodeWithSelector(
            Bank.ErrWard.selector, me, bank, File.file.selector
        ));
        File(bank).file('ceil', bytes32(WAD));

        // bank always wards itself
        vm.prank(bank);
        File(bank).file('ceil', bytes32(WAD));
        assertFalse(File(bank).wards(bank));

        // ward is warded
        vm.expectRevert(abi.encodeWithSelector(
            Bank.ErrWard.selector, me, bank, File.ward.selector
        ));
        File(bank).ward(me, true);
    }

}
