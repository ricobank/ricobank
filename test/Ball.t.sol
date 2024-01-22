pragma solidity ^0.8.19;

import { UniSetUp, PoolArgs, Asset } from "../test/UniHelper.sol";
import { INonfungiblePositionManager as INFPM } from './Univ3Interface.sol';
import { UniswapV3Adapter } from "../lib/feedbase/src/adapters/UniswapV3Adapter.sol";
import { ChainlinkAdapter } from "../lib/feedbase/src/adapters/ChainlinkAdapter.sol";
import { IUniWrapper } from '../lib/feedbase/src/adapters/UniswapV3Adapter.sol';
import {
    File, Bank, Vat, Vow, Vox, ERC20Hook, BaseHelper, BankDiamond, WethLike,
    Divider, Multiplier, Feedbase, Gem, GemFab, Ball, UniNFTHook
} from './RicoHelper.sol';
import 'forge-std/Test.sol';

contract BallTest is BaseHelper {
    bytes32 constant RAI_ETH_TAG  = "rai:eth";
    bytes32 constant RAI_REF_TAG  = "rai:ref";
    bytes32 constant RICO_DAI_TAG = "rico:dai";
    bytes32 constant wilk         = WETH_ILK;

    uint160 constant risk_price = X96;
    uint256 constant init_par   = RAY * 4;
    uint256 constant wethamt    = WAD;

    ERC20Hook        tokhook;
    UniNFTHook       unihook;
    ChainlinkAdapter cladapt;
    UniswapV3Adapter uniadapt;
    Divider          divider;
    Multiplier       multiplier;
    Feedbase         fb;
    address constant fsrc = 0xF33df33dF33dF33df33df33df33dF33DF33Df33D;

    GemFab           gf;

    INFPM npfm = INFPM(NFPM);

    address rico;
    address risk;
    address ricodai;
    address ricorisk;
    int256  safedart;

    bytes32[] ilks;

    uint initial_risk_supply = 1000000 * WAD;
    uint init_dust           = 90 * RAD / 2000;
    uint start_time;

    function advance_chainlink() internal {
        // time has skipped ahead while forked chainlink static
        // give adapters extra ttl equal to skipped time
        uint skipped = block.timestamp + 100_000 - start_time;
        bytes32[4] memory tags = [XAU_USD_TAG, DAI_USD_TAG, WETH_USD_TAG, RAI_ETH_TAG];
        for(uint i; i < tags.length; i++) {
            ChainlinkAdapter.Config memory config = cladapt.getConfig(tags[i]);
            config.ttl += skipped;
            cladapt.setConfig(tags[i], config);
        }
    }

    function look_poke() internal {
        advance_chainlink();
    }

    function setUp() public {
        start_time = block.timestamp;
        gf         = new GemFab();
        fb         = new Feedbase();

        // rico and risk created separately from ball
        // ball never wards them
        rico = address(gf.build(bytes32("Rico"), bytes32("RICO")));
        risk = address(gf.build(bytes32("Rico Riskshare"), bytes32("RISK")));

        address uniwrapper     = make_uniwrapper();
        uint160 sqrt_ratio_x96 = get_rico_sqrtx96(init_par);
        ricodai                = create_pool(rico, DAI, 500, sqrt_ratio_x96);
        ricorisk               = create_pool(rico, risk, RISK_FEE, risk_price);

        uniadapt   = new UniswapV3Adapter(IUniWrapper(uniwrapper));
        divider    = new Divider(address(fb));
        multiplier = new Multiplier(address(fb));
        cladapt    = new ChainlinkAdapter();

        tokhook = new ERC20Hook();
        unihook = new UniNFTHook(NFPM);

        Ball.IlkParams[] memory ips = new Ball.IlkParams[](2);

        // bank with ilks for weth and rai
        bank    = make_diamond();
        ilks    = new bytes32[](2);
        ilks[0] = wilk;
        ilks[1] = RAI_ILK;

        ips[0] = Ball.IlkParams(
            'weth',
            WETH,
            address(0),
            WETH_USD_AGG,
            RAY, // chop
            init_dust, // dust
            1000000001546067052200000000, // fee
            100000 * RAD, // line
            RAY, // liqr
            20000, // ttl
            1 // range
        );
        ips[1] = Ball.IlkParams(
            'rai',
            RAI,
            RAI_ETH_AGG,
            address(0),
            RAY, // chop
            init_dust, // dust
            1000000001546067052200000000, // fee
            100000 * RAD, // line
            RAY, // liqr
            20000, // ttl
            1 // range
        );

        address[] memory unigems = new address[](2);
        (unigems[0], unigems[1]) = (WETH, DAI);
        address[] memory unisrcs = new address[](2);
        (unisrcs[0], unisrcs[1]) = (fsrc, fsrc);
        bytes32[] memory unitags = new bytes32[](2);
        (unitags[0], unitags[1]) = (WETH_REF_TAG, DAI_REF_TAG);
        uint256[] memory uniliqrs = new uint[](2);
        (uniliqrs[0], uniliqrs[1]) = (RAY, RAY);

        Ball.UniParams memory ups = Ball.UniParams(
            ':uninft',                     // ilk
            1000000001546067052200000000,  // fee
            RAY,                           // chop
            init_dust,                     // dust
            100000 * RAD,                  // line
            8,                             // room
            uniwrapper,
            unigems,
            unisrcs,
            unitags,
            uniliqrs
        );

        Ball.BallArgs memory bargs = Ball.BallArgs(
            bank,
            address(fb),
            address(uniadapt),
            address(divider),
            address(multiplier),
            address(cladapt),
            address(tokhook),
            address(unihook),
            rico,
            risk,
            ricodai,
            ricorisk,
            DAI,
            DAI_USD_AGG,
            XAU_USD_AGG,
            init_par,
            100000 * WAD,
            20000, // ricodai
            BANKYEAR * 100,
            BANKYEAR, // daiusd
            BANKYEAR, // xauusd
            2,    // plat.pep
            RAY,  // plat.pop
            2,    // plot.pep
            RAY,  // plot.pop
            Bank.Ramp(block.timestamp, 1, RAY / BLN, RAY)
        );

        Ball ball = new Ball(bargs);

        BankDiamond(bank).transferOwnership(address(ball));
        uniadapt.ward(address(ball), true);
        divider.ward(address(ball), true);
        multiplier.ward(address(ball), true);
        cladapt.ward(address(ball), true);

        // setup bank and ilks
        ball.setup(bargs);
        ball.makeilk(ips[0]);
        ball.makeilk(ips[1]);
        ball.makeuni(ups);

        // transfer root access to self
        ball.approve(self);
        BankDiamond(bank).acceptOwnership();

        // give bank mint/burn power
        Gem(rico).ward(bank, true);
        Gem(risk).ward(bank, true);

        // need to wait some time for uni adapters to work
        skip(BANKYEAR / 2);
        look_poke();

        Gem(WETH).approve(bank, type(uint).max);
        WethLike(WETH).deposit{value: wethamt * 100}();
        Gem(risk).mint(address(this), initial_risk_supply);

        // find a rico borrow amount which will be safe by about 10%
        (bytes32 val,) = fb.pull(address(divider), WETH_REF_TAG);

        // weth * wethref = art * par
        safedart = int(wethamt * uint(val) / init_par * 10 / 11);
    }

    // apply to tests that create a surplus
    modifier _flap_after_ {
        _;
        Gem(risk).mint(self, 10000 * WAD);
        for(uint i; i < ilks.length; ++i) {
            Vat(bank).drip(ilks[i]);
        }

        uint pre_bank_risk = Gem(risk).balanceOf(bank);
        uint pre_bank_rico = Gem(rico).balanceOf(bank);
        uint pre_bank_joy  = Vat(bank).joy();
        uint pre_user_risk = Gem(risk).balanceOf(self);
        uint pre_user_rico = Gem(rico).balanceOf(self);
        uint pre_risk_sup  = Gem(risk).totalSupply();

        vm.expectCall(rico, abi.encodePacked(Gem.mint.selector));
        vm.expectCall(risk, abi.encodePacked(Gem.burn.selector));
        Vow(bank).keep(ilks);

        uint aft_bank_risk = Gem(risk).balanceOf(bank);
        uint aft_bank_rico = Gem(rico).balanceOf(bank);
        uint aft_bank_joy  = Vat(bank).joy();
        uint aft_user_risk = Gem(risk).balanceOf(self);
        uint aft_user_rico = Gem(rico).balanceOf(self);
        uint aft_risk_sup  = Gem(risk).totalSupply();

        // user should lose risk and gain rico
        // system should lose joy and decrease supply of risk
        // system tokens should remain zero

        assertEq(pre_bank_risk, aft_bank_risk);
        assertEq(pre_bank_rico, aft_bank_rico);
        assertGt(pre_bank_joy,  aft_bank_joy);
        assertGt(pre_user_risk, aft_user_risk);
        assertLt(pre_user_rico, aft_user_rico);
        assertGt(pre_risk_sup,  aft_risk_sup);
    }

    modifier _flop_after_ {
        _;
        vm.expectCall(risk, abi.encodePacked(Gem(risk).mint.selector));
        Vow(bank).keep(ilks);
    }

    modifier _balanced_after_ {
        _;
        // should not be any auctions
        uint me_risk_1 = Gem(risk).balanceOf(self);
        uint me_rico_1 = Gem(rico).balanceOf(self);

        Vow(bank).keep(ilks);

        uint me_risk_2 = Gem(risk).balanceOf(self);
        uint me_rico_2 = Gem(rico).balanceOf(self);

        assertEq(me_risk_1, me_risk_2);
        assertEq(me_rico_1, me_rico_2);
    }

    function test_basic_feeds() public {
        // at block 16445606 ethusd about 1554, xau  about 1925
        // initial par is 4, so ricousd should be 1925*4
        (bytes32 val,) = fb.pull(address(divider), RICO_REF_TAG);
        uint vox_price = uint(val);
        assertGt(uint(vox_price), init_par * 99 / 100);
        assertLt(uint(vox_price), init_par * 100 / 99);

        // should have a reasonable weth:ref (==weth:gold) price
        (val,) = fb.pull(address(divider), WETH_REF_TAG);
        assertClose(uint(val), 1554 * RAY / 1925, 100);
    }

    function test_eth_denominated_ilks_feed() public {
        // make sure ilk feeds combining properly
        look_poke();
        (bytes32 rai_ref_price,)  = fb.pull(address(divider), RAI_REF_TAG);
        (bytes32 weth_ref_price,) = fb.pull(address(divider), WETH_REF_TAG);
        (bytes32 rai_weth_price,)  = fb.pull(address(cladapt), RAI_ETH_TAG);
        assertClose(rdiv(uint(rai_ref_price), uint(weth_ref_price)), uint(rai_weth_price), 1000);
    }

    function test_ball_1() public {
        // simple bail with weth ilk
        Vat(bank).frob(wilk, self, abi.encodePacked(wethamt), safedart);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(wilk, self, abi.encodePacked(int(0)), safedart);
    }

    function test_fee_bail_flop() public _flop_after_ {
        // make the urn unsafe by accumulating
        Vat(bank).frob(wilk, self, abi.encodePacked(wethamt), safedart);

        // can't bail, not enough fees accumulated
        vm.expectRevert(Vat.ErrSafeBail.selector);
        Vat(bank).bail(wilk, self);

        // make the urn unsafe by accumulating a bunch of fees
        skip(BANKYEAR * 100);

        // revert bc feed data old
        vm.expectRevert(Vat.ErrSafeBail.selector);
        Vat(bank).bail(wilk, self);

        // keep accumulates fees and flaps
        look_poke();
        vm.expectCall(rico, abi.encodePacked(Gem.mint.selector));
        Vow(bank).keep(single(wilk));

        // shouldn't have enough to cover all the debt
        // so regardless of previous flap, should leave some deficit
        uint meweth = WethLike(WETH).balanceOf(self);
        Gem(rico).mint(self, 1000000 * WAD);
        Vat(bank).bail(wilk, self);
        assertGt(WethLike(WETH).balanceOf(self), meweth);
    }

    // frob, then flap (with wel == 100%), and check balanced
    function test_ball_pay_flap_success() public  _balanced_after_ {
        Vat(bank).frob(wilk, self, abi.encodePacked(wethamt), safedart);

        skip(BANKYEAR * 100); look_poke();

        uint art_pre = Vat(bank).urns(wilk, self);
        uint ink_pre = _ink(wilk, self);

        assertEq(Vow(bank).ramp().wel, RAY);
        vm.expectCall(rico, abi.encodePacked(Gem.mint.selector));
        Vow(bank).keep(ilks); // drips

        uint rack = Vat(bank).ilks(wilk).rack;
        uint dust = Vat(bank).ilks(wilk).dust;
        int  dart = -int((art_pre * rack - dust) / rack);

        Vat(bank).frob(wilk, self, abi.encodePacked(int(0)), dart);

        uint art_aft = Vat(bank).urns(wilk, self);
        uint ink_aft = _ink(wilk, self);
        assertEq(ink_aft, ink_pre);
        assertGt(art_aft, dust / rack * 999 / 1000);
        assertLt(art_aft, dust / rack * 1000 / 999);

        // balanced now because already kept
    }

    function test_ward() public {
        File(bank).file('ceil', bytes32(WAD));
        assertEq(BankDiamond(bank).owner(), address(this));

        vm.prank(VAULT);
        vm.expectRevert("Ownable: sender must be owner");
        File(bank).file('ceil', bytes32(WAD));

        BankDiamond(bank).transferOwnership(VAULT);
        assertEq(BankDiamond(bank).owner(), address(this));

        vm.prank(VAULT);
        vm.expectRevert("Ownable: sender must be owner");
        File(bank).file('ceil', bytes32(WAD));

        File(bank).file('ceil', bytes32(WAD));

        vm.prank(VAULT);
        BankDiamond(bank).acceptOwnership();
        assertEq(BankDiamond(bank).owner(), VAULT);

        vm.expectRevert("Ownable: sender must be owner");
        File(bank).file('ceil', bytes32(WAD));

        vm.prank(VAULT);
        File(bank).file('ceil', bytes32(WAD));
    }

    function test_bounds_fee() public {
        bytes32 gilk = 'gold';
        Vat(bank).init(gilk, address(0));

        // shouldn't be able to go under min
        vm.expectRevert(Bank.ErrBound.selector);
        Vat(bank).filk(gilk, 'fee', bytes32(RAY - 1));

        // test minimum...rack should stick
        Vat(bank).filk(gilk, 'fee', bytes32(RAY));

        skip(BANKYEAR);
        Vat(bank).drip(gilk);
        assertEq(Vat(bank).ilks(gilk).rack, RAY);

        // test max...rack should grow 10x/yr
        uint fee_max = Vat(bank).FEE_MAX();
        Vat(bank).filk(gilk, 'fee', bytes32(fee_max));

        skip(BANKYEAR * 2);
        Vat(bank).drip(gilk);
        assertClose(Vat(bank).ilks(gilk).rack, 100 * RAY, 1000000000000);

        // shouldn't be able to go over max
        vm.expectRevert(Bank.ErrBound.selector);
        Vat(bank).filk(gilk, 'fee', bytes32(fee_max + 1));
    }

    function test_bounds_rel() public {
        File(bank).file('rel', bytes32(0));

        uint rel_max = File(bank).REL_MAX();
        vm.expectRevert(Bank.ErrBound.selector);
        File(bank).file('rel', bytes32(rel_max + 1));
        File(bank).file('rel', bytes32(rel_max));

        File(bank).file('cel', bytes32(UINT256_MAX));
        uint wait = BANKYEAR - (block.timestamp - Vow(bank).ramp().bel);
        skip(wait);

        Vat(bank).filh(wilk, 'src', new bytes32[](0), bytes32(bytes20(fsrc)));
        File(bank).file('rudd.src', bytes32(bytes20(fsrc)));
        vm.prank(fsrc);
        fb.push(WETH_REF_TAG, bytes32(2 * init_par), UINT256_MAX);


        Vat(bank).frob(wilk, self, abi.encodePacked(int(WAD)), int(WAD));

        // prank a low but nonzero risk:rico price so no reflop error
        vm.startPrank(fsrc);
        fb.push(RISK_RICO_TAG, bytes32(uint(1)), UINT256_MAX);
        fb.push(WETH_REF_TAG, bytes32(uint(0)), UINT256_MAX);
        vm.stopPrank();

        // create some sin
        Vat(bank).bail(wilk, self);

        uint supply_pre = Gem(risk).totalSupply();
        Vow(bank).keep(empty);
        // 100 because rel, and 101 because of supply already there
        assertLt(Gem(risk).totalSupply(), supply_pre * 101);
        assertGt(Gem(risk).totalSupply(), supply_pre * 100);
    }

    function test_bounds_2() public {
        File(bank).file('way', bytes32(RAY));
        File(bank).file('wel', bytes32(0));
        File(bank).file('wel', bytes32(RAY));
        vm.expectRevert(Bank.ErrBound.selector);
        File(bank).file('wel', bytes32(RAY+1));

        File(bank).file('loot', bytes32(0));
        File(bank).file('loot', bytes32(RAY));
        vm.expectRevert(Bank.ErrBound.selector);
        File(bank).file('loot', bytes32(RAY+1));

        File(bank).file('how', bytes32(RAY));
        File(bank).file('how', bytes32(UINT256_MAX));
        vm.expectRevert(Bank.ErrBound.selector);
        File(bank).file('how', bytes32(RAY-1));

        File(bank).file('how', bytes32(RAY));
        uint cap_max = File(bank).CAP_MAX();
        File(bank).file('cap', bytes32(RAY));
        File(bank).file('cap', bytes32(cap_max));
        vm.expectRevert(Bank.ErrBound.selector);
        File(bank).file('cap', bytes32(cap_max+1));

        File(bank).file('how', bytes32(RAY * 3 / 2));
        File(bank).file('way', bytes32(RAY));

        Vox(bank).poke();

        File(bank).file('tip.src', bytes32(bytes20(self)));
        fb.push(RICO_REF_TAG, bytes32(0), UINT256_MAX);

        File(bank).file('way', bytes32(cap_max));
        File(bank).file('how', bytes32(uint(1000000000000003652500000000)));
        vm.expectRevert(Bank.ErrBound.selector);
        File(bank).file('way', bytes32(cap_max+1));

        skip(BANKYEAR);

        Vox(bank).poke();
        assertClose(Vat(bank).par(), 10 * init_par, 10000000000);

        File(bank).file('plot.pop', bytes32(RAY / 10));
        File(bank).file('plat.pop', bytes32(RAY / 10));
        File(bank).file('plot.pop', bytes32(RAY * 10));
        File(bank).file('plat.pop', bytes32(RAY * 10));

        vm.expectRevert(Bank.ErrBound.selector);
        File(bank).file('plot.pop', bytes32(RAY / 10 - 1));
        vm.expectRevert(Bank.ErrBound.selector);
        File(bank).file('plat.pop', bytes32(RAY / 10 - 1));
        vm.expectRevert(Bank.ErrBound.selector);
        File(bank).file('plot.pop', bytes32(RAY * 10 + 1));
        vm.expectRevert(Bank.ErrBound.selector);
        File(bank).file('plat.pop', bytes32(RAY * 10 + 1));
    }

}
