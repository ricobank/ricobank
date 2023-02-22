pragma solidity 0.8.18;

import "forge-std/Test.sol";
import { Swapper, UniSetUp, PoolArgs, Asset } from "../test/UniHelper.sol";

import { Ball, GemFabLike } from '../src/ball.sol';
import { INonfungiblePositionManager, IUniswapV3Pool } from '../src/TEMPinterface.sol';
import { Gem, GemFab } from '../lib/gemfab/src/gem.sol';
import { Feedbase } from '../lib/feedbase/src/Feedbase.sol';
import { Divider } from '../lib/feedbase/src/combinators/Divider.sol';
import { Medianizer } from '../lib/feedbase/src/Medianizer.sol';
import { UniswapV3Adapter } from "../lib/feedbase/src/adapters/UniswapV3Adapter.sol";
import { UniSwapper } from '../src/swap.sol';
import { Vat } from '../src/vat.sol';
import { Math } from '../src/mixin/math.sol';
import { WethLike } from '../test/RicoHelper.sol';
import {ChainlinkAdapter} from "../lib/feedbase/src/adapters/ChainlinkAdapter.sol";
import {TWAP} from "../lib/feedbase/src/combinators/TWAP.sol";
import {Progression} from "../lib/feedbase/src/combinators/Progression.sol";
import { Vow } from "../src/vow.sol";
import {UniFlower} from '../src/flow.sol';

contract BallTest is Test, UniSetUp, Math {
    bytes32 internal constant WILK = "weth";
    uint8   public immutable EXACT_IN  = 0;
    uint8   public immutable EXACT_OUT = 1;
    address internal constant DAI   = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant WETH  = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WETH_DAI_POOL  = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
    // TODO these should have dashes
    bytes32 internal constant WETH_ILK = "weth";
    bytes32 internal constant WETH_DAI_TAG = "wethdai";
    bytes32 internal constant WETH_RICO_TAG = "wethrico";
    bytes32 internal constant RICO_DAI_TAG = "ricodai";
    bytes32 internal constant DAI_RICO_TAG = "dairico";
    bytes32 internal constant XAU_USD_TAG = "xauusd";
    bytes32 internal constant XAU_DAI_TAG = "xauusd";
    bytes32 internal constant DAI_USD_TAG = "daiusd";
    bytes32 internal constant XAU_RICO_TAG = "xaurico";
    bytes32 internal constant REF_RICO_TAG = "refrico";
    bytes32 internal constant RICO_REF_TAG = "ricoref";
    ChainlinkAdapter cladapt;
    UniswapV3Adapter adapt;
    Divider divider;
    Progression progression;
    TWAP twap;
    Medianizer mdn;
    Feedbase fb;
    GemFabLike gf;
    address me;
    INonfungiblePositionManager npfm = INonfungiblePositionManager(
        0xC36442b4a4522E871399CD717aBDD847Ab11FE88
    );
    address COMPOUND_CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    Swapper swap;
    uint256 constant public BANKYEAR = (365 * 24 + 6) * 3600;
    address rico;
    address risk;
    uint constant INIT_SQRTPAR = RAY * 2;
    uint constant INIT_PAR = (INIT_SQRTPAR ** 2) / RAY;
    uint constant wethricoprice = 1500 * RAY * RAY / INIT_PAR;
    uint constant wethamt = WAD;
    int constant dart = int(wethamt * wethricoprice / INIT_PAR);
    bytes32[] ilks;
    IUniswapV3Pool public ricorisk;
    uint DEV_FUND_RISK = 1000000 * WAD;

    Vat vat;
    Vow vow;
    UniFlower flow;

    function advance_chainlink() internal {
        // chainlink adapter advances from chainlink time
        // prank ttl to uint max
        (bytes32 v,) = fb.pull(address(cladapt), XAU_USD_TAG);
        vm.prank(address(cladapt));
        fb.push(XAU_USD_TAG, v, type(uint).max);
        (v,) = fb.pull(address(cladapt), DAI_USD_TAG);
        vm.prank(address(cladapt));
        fb.push(DAI_USD_TAG, v, type(uint).max);
    }

    function look_poke() internal {
        advance_chainlink();
        adapt.look(WETH_DAI_TAG);
        adapt.look(RICO_DAI_TAG);

        divider.poke(WETH_RICO_TAG);
        divider.poke(DAI_RICO_TAG);
        divider.poke(XAU_DAI_TAG);
        divider.poke(XAU_RICO_TAG);

        twap.poke(XAU_RICO_TAG);
        progression.poke(REF_RICO_TAG);
        divider.poke(RICO_REF_TAG);

        mdn.poke(WETH_RICO_TAG);
        mdn.poke(RICO_REF_TAG);
    }

    function setUp() public {
        address aweth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        uint gas = gasleft();
        gf = GemFabLike(address(new GemFab()));
        fb = new Feedbase();

        Ball.IlkParams[] memory ips = new Ball.IlkParams[](1);
        ilks = new bytes32[](1);
        ilks[0] = WETH_ILK;
        assertEq(ilks.length, 1);
        ips[0] = Ball.IlkParams(
            'weth',
            WETH,
            WETH_DAI_POOL,
            RAD, // chop
            90 * RAD, // dust
            1000000001546067052200000000, // fee
            100000 * RAD, // line
            RAY, // liqr
            UniFlower.Ramp(WAD / 1000, WAD, block.timestamp, 1, WAD / 100),
            20000, // ttl
            BANKYEAR / 4 // range
        );
        UniFlower.Ramp memory stdramp = UniFlower.Ramp(
            WAD, WAD, block.timestamp, 1, WAD / 100
        );
        Ball.BallArgs memory bargs = Ball.BallArgs(
            address(gf),
            address(fb),
            aweth,
            factory,
            router,
            INIT_SQRTPAR,
            100000 * RAD,
            20000, // ricodai
            BANKYEAR / 4,
            BANKYEAR, // daiusd
            BANKYEAR, // xauusd
            10000, // twap
            BANKYEAR,
            block.timestamp, // prog
            block.timestamp + BANKYEAR * 10,
            BANKYEAR / 12,
            stdramp,
            stdramp,
            stdramp
        );

        Ball ball = new Ball(bargs, ips);

        skip(BANKYEAR / 2);
        uint usedgas     = gas - gasleft();
        uint expectedgas = 27136299;
        if (usedgas < expectedgas) {
            console.log("ball saved %s gas...currently %s", expectedgas - usedgas, usedgas);
        }
        if (usedgas > expectedgas) {
            console.log("ball gas increase by %s...currently %s", usedgas - expectedgas, usedgas);
        }

        swap = new Swapper();
        rico = ball.rico();
        risk = ball.risk();
        swap.approveGem(DAI, router);
        swap.approveGem(rico, router);
        swap.setSwapRouter(router);
        // Create a path to swap UNI for WETH in a single hop
        address [] memory addr2 = new address[](2);
        uint24  [] memory fees1 = new uint24 [](1);
        addr2[0] = DAI;
        addr2[1] = ball.rico();
        fees1[0] = 500;
        bytes memory fore;
        bytes memory rear;
        (fore, rear) = create_path(addr2, fees1);
        swap.setPath(DAI, rico, fore, rear);

        vm.prank(VAULT);
        Gem(DAI).transfer(address(this), 500 * WAD);

        Gem(DAI).transfer(address(swap), 300 * WAD);
        uint res = swap.swap(DAI, rico, address(swap), EXACT_IN, 300 * WAD, 1);
        // pool has no liquidity
        assert(swap.SWAP_ERR() == res);

        vat = ball.vat();
        Gem(WETH).approve(address(vat), type(uint).max);
        me   = address(this);
        WethLike(WETH).deposit{value: wethamt * 100}();
        // try to frob 1 weth for at least $1k...shouldn't work because no look
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(WETH_ILK, me, int(wethamt), dart);

        adapt = ball.adapt();
        divider = ball.divider();
        (,,address _mdn,,,,,,,,,) = vat.ilks(WETH_ILK);
        mdn = Medianizer(_mdn);
 
        cladapt = ball.cladapt();
        twap = ball.twap();
        progression = ball.progression();

        cladapt.look(XAU_USD_TAG);
        cladapt.look(DAI_USD_TAG);

        look_poke();

        vow = ball.vow();

        uint daiamt = 10000 * WAD;
        vm.prank(COMPOUND_CDAI);
        Gem(DAI).transfer(address(this), daiamt * 10);
        Gem(rico).mint(address(this), daiamt * RAY / INIT_SQRTPAR);
        join_pool(PoolArgs(
            Asset(rico, daiamt * RAY / INIT_SQRTPAR), Asset(DAI, daiamt),
            500,
            uint160(INIT_SQRTPAR * X96 / RAY),
            uint160(INIT_SQRTPAR * X96 / RAY) * 99 / 100,
            uint160(INIT_SQRTPAR * X96 / RAY) * 100 / 99, 10
        ));

        flow = ball.flow();

        Gem(risk).mint(address(this), DEV_FUND_RISK);
    }

    modifier _flap_after_ {
        _;
        uint rico_before = Gem(rico).balanceOf(address(flow));
        uint aid = vow.keep(ilks);
        uint rico_after = Gem(rico).balanceOf(address(flow));
        assertGt(rico_after, rico_before);

        // fund the pool
        // tick spacing 60 for 0.3%
        join_pool(PoolArgs(
            Asset(rico, Gem(rico).balanceOf(me)), Asset(risk, 10000 * WAD),
            3000, X96, X96 * 99 / 100, X96 * 100 / 99, 60
        ));
        rico_before = Gem(rico).balanceOf(address(flow));
        flow.glug(aid);
        rico_after = Gem(rico).balanceOf(address(flow));
        assertLt(rico_after, rico_before);
    }

    modifier _flop_after_ {
        _;
        uint risk_before = Gem(risk).balanceOf(address(flow));
        uint aid = vow.keep(ilks);
        uint risk_after = Gem(risk).balanceOf(address(flow));
        assertGt(risk_after, risk_before);

        // fund the pool
        // tick spacing 60 for 0.3%
        join_pool(PoolArgs(
            Asset(rico, Gem(rico).balanceOf(me)), Asset(risk, 10000 * WAD),
            3000, X96, X96 * 99 / 100, X96 * 100 / 99, 60
        ));
        risk_before = Gem(risk).balanceOf(address(flow));
        flow.glug(aid);
        risk_after = Gem(risk).balanceOf(address(flow));
        assertLt(risk_after, risk_before);
    }

    modifier _balanced_after_ {
        _;
        uint aid = vow.keep(ilks);
        assertEq(aid, 0);
    }

    function test_basic() public {
        (bytes32 price, uint ttl) = fb.pull(address(mdn), RICO_REF_TAG);
        assertEq(uint(price) / RAY, INIT_PAR / RAY);
        (price, ttl) = fb.pull(address(mdn), WETH_RICO_TAG);
        // ether price about 1600 rn
        assertGt(uint(price) / RAY, 1000 * RAY / INIT_PAR);
        assertLt(uint(price) / RAY, 2000 * RAY / INIT_PAR);
    }

    function test_ball() public {
        vat.frob(WETH_ILK, me, int(wethamt), dart);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(WETH_ILK, me, 0, dart);
    }

    function test_fee_bail_flop() public _flop_after_ {
        vat.frob(WETH_ILK, me, int(wethamt), dart);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(WETH_ILK, me);
        skip(BANKYEAR * 100);
        // revert bc feed data old
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(WETH_ILK, me);
        look_poke();
        uint aid = vow.bail(WETH_ILK, me);
        flow.glug(aid);
    }


    function test_ball_flap() public _flap_after_ {
        vat.frob(WETH_ILK, me, int(wethamt), dart);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(WETH_ILK, me);
        skip(BANKYEAR * 100);
    }

    // user pays down the urn first, then try to flap
    function test_ball_pay_flap_fail() public {
        vat.frob(WETH_ILK, me, int(wethamt), dart);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(WETH_ILK, me);
        skip(BANKYEAR * 100); advance_chainlink(); look_poke();

        (uint inkleft,uint artleft) = vat.urns(WETH_ILK, me);
        Gem(rico).mint(me, artleft);
        vat.frob(WETH_ILK, me, -int(inkleft), -int(artleft));
        (inkleft, artleft) = vat.urns(WETH_ILK, me);
        assertEq(inkleft, 0);
        assertEq(artleft, 0);
        // can't keep because there was never a drip
        vm.expectRevert(UniFlower.ErrTinyFlow.selector);
        vow.keep(ilks);
    }

    function test_ball_pay_flap_success() public  _balanced_after_ {
        vat.frob(WETH_ILK, me, int(wethamt), dart);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(WETH_ILK, me);
        skip(BANKYEAR * 100); look_poke();

        (uint inkleft,uint artleft) = vat.urns(WETH_ILK, me);
        vow.keep(ilks); // drips
        Gem(rico).mint(me, artleft * 1000);
        vat.frob(WETH_ILK, me, -int(inkleft), -int(artleft));
        (inkleft, artleft) = vat.urns(WETH_ILK, me);
        assertEq(inkleft, 0);
        assertEq(artleft, 0);
        // balanced now because already kept
    }

}
