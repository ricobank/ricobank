// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import { Ball } from '../src/ball.sol';
import { VatLike, GemLike, Flow } from '../src/abi.sol';
import { Vat } from '../src/vat.sol';
import { Vow } from '../src/vow.sol';
import { BalancerFlower } from '../src/flow.sol';
import { RicoSetUp } from "./RicoHelper.sol";
import { Asset, BalSetUp, PoolArgs } from "./BalHelper.sol";

contract Usr {
    Vat public vat;
    Vow public vow;
    constructor(Vat vat_, Vow vow_) {
        vat = vat_;
        vow = vow_;
    }
    function frob(bytes32 ilk, address u, int dink, int dart) public {
        vat.frob(ilk, u, dink, dart);
    }
    function bail(bytes32 ilk, address usr) public {
        vow.bail(ilk, usr);
    }
    function try_call(address addr, bytes calldata data) external returns (bool) {
        bytes memory _data = data;
        assembly {
            let ok := call(gas(), addr, 0, add(_data, 0x20), mload(_data), 0, 0)
            let free := mload(0x40)
            mstore(free, ok)
            mstore(0x40, add(free, 32))
            revert(free, 32)
        }
    }
    function can_frob(bytes32 ilk, address u, int dink, int dart) public returns (bool) {
        string memory sig = "frob(bytes32,address,int256,int256)";
        bytes memory data = abi.encodeWithSignature(sig, ilk, u, dink, dart);

        bytes memory can_call = abi.encodeWithSignature("try_call(address,bytes)", vat, data);
        (bool ok, bytes memory success) = address(this).call(can_call);

        ok = abi.decode(success, (bool));
        if (ok) return true;
        return false;
    }

    function approve(address gem) public {
        GemLike(gem).approve(address(vat), type(uint).max);
    }
}


contract DssJsTest is Test, RicoSetUp {
    uint256 public init_join = 1000;
    uint stack = WAD * 10;
    bytes32[] ilks;
    bytes32 pool_id_rico_risk;
    bytes32 pool_id_gold_rico;
    address me;
    Usr ali;
    Usr bob;
    Usr cat;
    address a;
    address b;
    address c;
    bytes32 i0;
    GemLike gem;
    GemLike joy;
    uint rico_gemrico = 10000 * WAD;
    uint goldprice = 40 * RAY / 110;
    uint gembal = rico_gemrico * goldprice / RAY;
    uint constant rico_riskrico = 10000 * WAD;
    uint total_pool_rico = rico_gemrico + rico_riskrico;
    uint constant total_pool_risk = 10000 * WAD;
    uint ceil = total_pool_rico + 300 * WAD;

    function init_gem(uint init_mint) public {
        gold = GemLike(address(gemfab.build(bytes32("Gold"), bytes32("GOLD"))));
        gold.mint(self, init_mint);
        gold.approve(address(vat), type(uint256).max);
        vat.init(gilk, address(gold), self, gtag);
        vat.filk(gilk, bytes32('chop'), RAD);
        vat.filk(gilk, bytes32("line"), init_mint * 10 * RAY);
        //vat.filk(gilk, bytes32('fee'), 1000000001546067052200000000);  // 5%
        feed.push(gtag, bytes32(RAY), block.timestamp + 1000);
        agold = address(gold);
        vow.grant(agold);
    }

    // todo frob rico.mint
    function _gift(address usr, uint amt) internal {
        rico.transfer(usr, amt);
    }

    function setUp() public {
        me = address(this);
        make_bank();
        joy = rico;
        init_gem(gembal);
        gem = gold;
        ilks.push(gilk);
        gem.approve(address(vat), UINT256_MAX);

        i0 = ilks[0];

        // vat init
        vat.file('ceil', ceil * RAD);
        vat.filk(i0, 'line', 1000 * RAD);

        feed.push(gtag, bytes32(RAY), block.timestamp + 1000);

        gem.approve(BAL_VAULT, UINT256_MAX);
        rico.approve(BAL_VAULT, UINT256_MAX);
        risk.approve(BAL_VAULT, UINT256_MAX);
        gem.approve(address(flow), UINT256_MAX);
        rico.approve(address(flow), UINT256_MAX);
        risk.approve(address(flow), UINT256_MAX);

        // RICO_mint
        rico.mint(me, total_pool_rico);
        risk.mint(me, total_pool_risk);

        // connecting flower
        flow.setVault(BAL_VAULT);
        flow.approve_gem(address(gem));

        // create pool
        Asset memory gold_rico_asset = Asset(address(gold), 5 * WAD / 10, gembal);
        Asset memory rico_gold_asset = Asset(address(rico), 5 * WAD / 10, rico_gemrico);
        Asset memory rico_risk_asset = Asset(address(rico), 5 * WAD / 10, rico_riskrico);
        Asset memory risk_rico_asset = Asset(address(risk), 5 * WAD / 10, total_pool_risk);

        PoolArgs memory rico_risk_args = PoolArgs(risk_rico_asset, rico_risk_asset, "mock", "MOCK", WAD / 100);
        PoolArgs memory gold_rico_args = PoolArgs(gold_rico_asset, rico_gold_asset, "mock", "MOCK", WAD / 100);

        pool_id_gold_rico = create_and_join_pool(gold_rico_args);
        pool_id_rico_risk = create_and_join_pool(rico_risk_args);
        flow.setPool(address(gem), address(rico), pool_id_gold_rico);
        flow.setPool(address(risk), address(rico), pool_id_rico_risk);
        flow.setPool(address(rico), address(risk), pool_id_rico_risk);

        assertEq(gem.balanceOf(me), 0);
        assertEq(rico.balanceOf(me), 0);
        assertEq(risk.balanceOf(me), 0);

        // link vat to vow
        vow.link('vat', address(vat));

        // link flow to vow
        vow.link('flow', address(flow));
        vow.grant(address(gem));

        flow.ward(address(vow), true);
        vow.ward(address(flow), true);

        // link rico, risk to vow
        vow.link('RICO', address(rico));
        vow.link('RISK', address(risk));
        vow.grant(address(rico));
        vow.grant(address(risk));

        // risk ward vow
        risk.ward(address(vow), true);

        // vat ward, hope vow
        vat.ward(address(vow), true);

        ali = new Usr(vat, vow);
        bob = new Usr(vat, vow);
        cat = new Usr(vat, vow);
        ali.approve(address(gem));
        bob.approve(address(gem));
        cat.approve(address(gem));
        a = address(ali);
        b = address(bob);
        c = address(cat);
    }

    function _slip(GemLike g, address usr, uint amt) internal {
        g.mint(usr, amt);
    }

    function assertRange(uint actual, uint expected, uint tolerance) internal {
        assertGe(actual, expected - tolerance * expected / WAD);
        assertLe(actual, expected + tolerance * expected / WAD);
    }
}

contract DssVatTest is DssJsTest {
    function _vat_setUp() internal {}
    modifier _vat_ { _vat_setUp(); _; }

    function _ink(bytes32 ilk, address usr) internal view returns (uint) {
        (uint ink,) = vat.urns(ilk, usr);
        return ink;
    }

    function _art(bytes32 ilk, address usr) internal view returns (uint) {
        (,uint art) = vat.urns(ilk, usr);
        return art;
    }
}

contract DssFrobTest is DssVatTest {

    function _frob_setUp() internal {
        _vat_setUp();
        assertEq(gem.balanceOf(me), 0);
        assertEq(GemLike(gem).balanceOf(me), 0);
        gem.mint(me, 1000 * WAD);
        feed.push(gtag, bytes32(RAY), block.timestamp + 1000);
        vat.filk(i0, 'line', 1000 * RAD);
    }
    modifier _frob_ { _frob_setUp(); _; }

    function test_setup() public _frob_ {
        assertEq(gem.balanceOf(me), 1000 * WAD);
        assertEq(gem.balanceOf(me), 1000 * WAD);
    }

    function test_lock() public _frob_ {
        assertEq(_ink(i0, me), 0);
        assertEq(gem.balanceOf(me), 1000 * WAD);
        vat.frob(i0, me, int(6 * WAD), 0);
        assertEq(_ink(i0, me), 6 * WAD);
        assertEq(gem.balanceOf(me), 994 * WAD);
        vat.frob(i0, me, -int(6 * WAD), 0);
        assertEq(_ink(i0, me), 0);
        assertEq(gem.balanceOf(me), 1000 * WAD);
    }

    function test_calm() public _frob_ {
        // calm means that the debt ceiling is not exceeded
        // it's ok to increase debt as long as you remain calm
        vat.filk(i0, 'line', 10 * RAD);
        vat.frob(i0, me, int(10 * WAD), int(9 * WAD));
        // only if under debt ceiling
        vm.expectRevert(Vat.ErrDebtCeil.selector);
        vat.frob(i0, me, 0, int(2 * WAD));
    }

    function test_cool() public _frob_ {
        // cool means that the debt has decreased
        // it's ok to be over the debt ceiling as long as you're cool
        vat.filk(i0, 'line', 10 * RAD);
        vat.frob(i0, me, int(10 * WAD), int(8 * WAD));
        vat.filk(i0, 'line', 5 * RAD);
        // can decrease debt when over ceiling
        vat.frob(i0, me, 0, -int(WAD));
    }

    function test_safe() public _frob_ {
        // safe means that the cdp is not risky
        // you can't frob a cdp into unsafe
        vat.frob(i0, me, int(10 * WAD), int(5 * WAD));
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(i0, me, 0, int(6 * WAD));
    }

    function test_nice() public _frob_ {
        // nice means that the collateral has increased or the debt has
        // decreased. remaining unsafe is ok as long as you're nice

        vat.frob(i0, me, int(10 * WAD), int(10 * WAD));
        feed.push(gtag, bytes32(RAY / 2), block.timestamp + 1000);
        // debt can't increase if unsafe
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(i0, me, 0, int(WAD));
        // debt can decrease
        vat.frob(i0, me, 0, -int(WAD));
        // ink can't decrease
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(i0, me, -int(WAD), 0);
        // ink can increase
        vat.frob(i0, me, int(WAD), 0);

        // cdp is still unsafe
        // ink can't decrease, even if debt decreases more
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(i0, me, -int(2 * WAD), -int(4 * WAD));

        // debt can't increase, even if ink increases more
        vm.expectRevert(Vat.ErrNotSafe.selector);
        vat.frob(i0, me, int(5 * WAD), int(WAD));


        // ink can decrease if end state is safe
        vat.frob(i0, me, -int(WAD), -int(4 * WAD));
        feed.push(gtag, bytes32(RAY * 2 / 5), block.timestamp + 1000);
        // debt can increase if end state is safe
        vat.frob(i0, me, int(5 * WAD), int(WAD));
    }

    function test_alt_callers() public _frob_ {

        _slip(gem, a, 20 * WAD);
        _slip(gem, b, 20 * WAD);
        _slip(gem, c, 20 * WAD);

        ali.frob(i0, a, int(10 * WAD), int(5 * WAD));

        // anyone can lock
        assertTrue(ali.can_frob(i0, a, int(WAD), 0));
        assertTrue(bob.can_frob(i0, b, int(WAD), 0));
        assertTrue(cat.can_frob(i0, c, int(WAD), 0));

        // but only with own gems - N/A no v or w

        // only the lad can free
        assertTrue(ali.can_frob(i0, a, -int(WAD), 0));
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        bob.frob(i0, a, -int(WAD), 0);
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        cat.frob(i0, a, -int(WAD), 0);
        // the lad can free to anywhere - N/A no v or w

        // only the lad can draw
        assertTrue(ali.can_frob(i0, a, 0, int(WAD)));
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        bob.frob(i0, a, 0, int(WAD));
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        cat.frob(i0, a, 0, int(WAD));
        // lad can draw to anywhere - N/A no v or w

        rico.mint(b, WAD + 1);  // +1 for rounding in system's favour
        rico.mint(c, WAD + 1);

        // anyone can wipe
        assertTrue(ali.can_frob(i0, a, 0, -int(WAD)));
        assertTrue(bob.can_frob(i0, a, 0, -int(WAD)));
        assertTrue(cat.can_frob(i0, a, 0, -int(WAD)));
        // but only with their own dai - N/A no v or w
    }

    function test_hope() public _frob_ {
        _slip(gem, a, 20 * WAD);
        _slip(gem, b, 20 * WAD);
        _slip(gem, c, 20 * WAD);

        ali.frob(i0, a, int(10 * WAD), int(5 * WAD));

        // only owner can do risky actions
        assertTrue(ali.can_frob(i0, a, 0, int(WAD)));
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        bob.frob(i0, a, 0, int(WAD));
        vm.expectRevert(Vat.ErrWrongUrn.selector);
        cat.frob(i0, a, 0, int(WAD));

        // unless they hope another user - N/A no hope
    }

    function test_dust() public _frob_ {
        rico.mint(me, 1); // +1 for rounding in system's favour
        vat.frob(i0, me, int(9 * WAD), int(WAD));
        vat.filk(i0, 'dust', 5 * RAD);
        vm.expectRevert(Vat.ErrUrnDust.selector);
        vat.frob(i0, me, int(5 * WAD), int(2 * WAD));
        vat.frob(i0, me, 0, int(5 * WAD));
        vm.expectRevert(Vat.ErrUrnDust.selector);
        vat.frob(i0, me, 0, -int(5 * WAD));
        vat.frob(i0, me, 0, -int(6 * WAD));
    }
}

contract DssBiteTest is DssVatTest {
    GemLike gov;

    function _bite_setUp() internal {
        _vat_setUp();
        gov = risk;
        gov.mint(me, 100 * WAD);

        // jug N/A
        //   rico has fee, no jug
        //   dss setup doesn't actually set the fee, just creates the jug

        gold.mint(me, 1000 * WAD);

        feed.push(gtag, bytes32(RAY), block.timestamp + 1000);
        vat.filk(i0, 'line', 1000 * RAD);
        // cat.box N/A bail liquidates entire urn
        vat.filk(i0, 'chop', RAY);

        gold.approve(address(vat), UINT256_MAX);
        // gov approve flap N/A not sure what to do with gov atm...

        curb(address(gold), UINT256_MAX, WAD, block.timestamp, 1);
        curb(address(rico), UINT256_MAX, WAD, block.timestamp, 1);
        curb(address(risk), UINT256_MAX, WAD, block.timestamp, 1);
    }

    modifier _bite_ { _bite_setUp(); _; }

    function testdunk(uint rel, uint vel) internal {
        vow.pair(address(gold), 'rel', rel);
        vow.pair(address(gold), 'vel', vel);
        vow.pair(address(gov), 'rel', rel);
        vow.pair(address(gov), 'vel', vel);
        uint _rel; uint _vel; uint _bel; uint _cel; uint _del;
        (_vel, _rel, _bel, _cel, _del) = flow.ramps(address(vow), address(gold));
        assertEq(_rel, rel);
        assertEq(_vel, vel);
        (_vel, _rel, _bel, _cel, _del) = flow.ramps(address(vow), address(gov));
        assertEq(_rel, rel);
        assertEq(_vel, vel);
    }

    function test_set_dunk_multiple_ilks() public _bite_ {
        testdunk(0, 0);
        testdunk(WAD / 100, WAD / 50);
    }

    // test_cat_set_box
    //   N/A vow liquidates entire urn, no box

    // test_bite_under_dunk
    //   N/A no dunk analogue, vow can only bail entire urn

    // test_bite_over_dunk
    //   N/A no dunk analogue, vow can only bail entire urn


    function vow_Awe() internal view returns (uint) { return vat.sin(address(vow)); }

    // vow_Woe N/A - no debt queue in vow

    function test_happy_bite() public _bite_ {
        // set ramps high so flip flips whole gem balance
        curb(address(gold), 1000 * WAD, 1000 * WAD, 0, 1);
        // dss: spot = tag / (par . mat), tag=5, mat=2
        // rico: mark = feed.val = 2.5
        // create urn (push, frob)
        feed.push(gtag, bytes32(RAY * 5 / 2), block.timestamp + 1000);
        vat.frob(i0, me, int(40 * WAD), int(100 * WAD));

        // tag=4, mat=2
        // make urn unsafe, set liquidation penalty
        feed.push(gtag, bytes32(RAY * 2), block.timestamp + 1000);
        vat.filk(i0, 'chop', RAY * 11 / 10);

        assertEq(_ink(i0, me), 40 * WAD);
        assertEq(_art(i0, me), 100 * WAD);
        // Woe N/A - no debt queue (Sin) in vow
        assertEq(gem.balanceOf(me), 960 * WAD);

        // => bite everything
        // dss checks joy 0 before tend, rico checks before bail
        assertEq(rico.balanceOf(address(vow)), 0);
        // cat.file dunk N/A vow always bails whole urn
        // cat.litter N/A vow always bails urn immediately
        assertEq(rico.balanceOf(address(vow)), 0);
        vow.bail(i0, me);
        flow.glug(bytes32(flow.count())); // glug succeeds because gold's bel is low
        assertEq(_ink(i0, me), 0);
        assertEq(_art(i0, me), 0);
        // vow.sin(now) N/A rico vow has no debt queue

        // tend, dent, deal N/A rico flips immediately, no tend dent deal
        {
            uint expected = 110 * WAD;
            uint actual = rico.balanceOf(address(vow));
            uint tolerance = expected / 5;
            assertGe(actual, expected - tolerance);
            assertLe(actual, expected + tolerance);
        }

        skip(1);
        vow.keep(ilks);
        flow.glug(bytes32(flow.count()));
    }

    // test_partial_litterbox
    //   N/A bail liquidates whole urn, dart == art

    // testFail_fill_litterbox
    //   N/A bail liquidates whole urn

    // testFail_dusty_litterbox
    //   N/A bail liquidates whole urn, and there's no liquidation limit
    //   besides debt ceiling

    // test_partial_litterbox_multiple_bites
    //   N/A bail liquidates whole urn in one tx, no liquidation limit (litterbox)

    // testFail_null_auctions_dart_realistic_values
    //   N/A vow has no dustiness check, just liquidates entire urn

    // testFail_null_auctions_dart_artificial_values
    //   N/A no box, bail liquidates entire urn immediately

    // testFail_null_auctions_dink_artificial_values
    //   TODO might be relevant, need to update flow.  right now bill isn't even used, so rico trades all the ink
    //   with balancer.  N/A for now

    // testFail_null_auctions_dink_artificial_values_2
    //   N/A no dunk, vow always bails whole urn

    // testFail_null_spot_value
    //   N/A bail amount doesn't depend on spot, only reverts if urn is safe

    function testFail_vault_is_safe() public _bite_ {
        feed.push(gtag, bytes32(RAY * 5 / 2), block.timestamp + 1000);
        vat.frob(i0, me, int(100 * WAD), int(150 * WAD));

        assertEq(_ink(i0, me), 100 * WAD);
        assertEq(_art(i0, me), 150 * WAD);
        // Woe N/A - no debt queue (Sin) in vow
        assertEq(gem.balanceOf(me), 900 * WAD);

        // dunk, litter N/A bail liquidates whole urn in one tx, no litterbox
        vm.expectRevert('ERR_SAFE');
        vow.bail(i0, me);
    }

    function test_floppy_bite() public _bite_ {
        feed.push(gtag, bytes32(RAY * 5 / 2), block.timestamp + 1000);
        vat.frob(i0, me, int(40 * WAD), int(100 * WAD));
        feed.push(gtag, bytes32(2 * RAY), block.timestamp + 1000);

        // mimic dss auction rates...need to flop wad(1000) risk
        uint bailamt = 30 * WAD;
        uint riskamt = 10 * WAD;
        curb(address(gold), bailamt, WAD, block.timestamp, 1);
        curb(address(risk), riskamt, WAD, block.timestamp, 1);

        assertEq(gov.balanceOf(address(flow)), 0);
        // dunk N/A bail always liquidates whole urn
        // vow.sin N/A no debt queue
        assertEq(vat.sin(address(vow)), 0);
        assertEq(rico.balanceOf(address(vow)), 0);
        assertEq(rico.balanceOf(address(vow)), 0);
        vow.bail(i0, me);
        // glug fails since no time has passed
        bytes32 aid = bytes32(flow.count());
        vm.expectRevert(BalancerFlower.ErrSwapFail.selector);
        flow.glug(aid);
        assertEq(vat.sin(address(vow)), 100 * RAD);
        assertEq(rico.balanceOf(address(vow)), 0);

        skip(1);
        // todo test keep without skip, always reverts on deficit with or without glug
        flow.glug(bytes32(flow.count()));

        assertEq(vat.sin(address(vow)), 100 * RAD);
        uint ricobought = rico.balanceOf(address(vow));
        assertRange(ricobought, bailamt * RAY / goldprice, WAD / 50);

        vow.keep(ilks);
        flow.glug(bytes32(flow.count()));
        assertEq(vat.sin(address(vow)), 100 * RAD - (ricobought - 1) * RAY); // leaves 1 rico to save gas
        assertRange(rico.balanceOf(address(vow)), riskamt, WAD / 50);
        skip(1); vow.keep(ilks); flow.glug(bytes32(flow.count()));
        skip(1); vow.keep(ilks); flow.glug(bytes32(flow.count()));
        assertEq(vat.sin(address(vow)), RAY); // healed all but 1 rico to save gas
        assertEq(rico.balanceOf(address(vow)), 1);
    }

    // todo maybe a similar test but get the surplus using frob/bail?
    function test_flappy_bite() public _bite_ {
        rico.mint(address(vow), 100 * WAD);
        assertEq(rico.balanceOf(address(vow)), 100 * WAD);
        assertEq(gov.balanceOf(me), 100 * WAD);

        curb(address(rico), 100 * WAD, WAD, block.timestamp, 1);
        assertEq(vow_Awe(), 0);

        vow.keep(ilks);
        uint aid = flow.count();
        vm.expectRevert(BalancerFlower.ErrSwapFail.selector);
        flow.glug(bytes32(aid));

        assertEq(rico.balanceOf(address(vow)), 0);
        assertEq(vow_Awe(), 0);
        assertEq(gov.balanceOf(address(vow)), 0);

        skip(1);
        flow.glug(bytes32(flow.count()));
        assertEq(rico.balanceOf(address(vow)), 0);
        assertEq(vow_Awe(), 0);
        assertGt(gov.balanceOf(address(vow)), 0);

        vow.keep(ilks);
        aid = flow.count();
        // no surplus or deficit, keep didn't create an auction
        // previous auction has already been deleted
        vm.expectRevert(BalancerFlower.ErrEmptyAid.selector);
        flow.glug(bytes32(aid));
        assertEq(rico.balanceOf(address(vow)), 0);
        assertEq(vow_Awe(), 0);
        assertEq(gov.balanceOf(address(vow)), 0);
    }
}

contract DssFoldTest is DssVatTest {
    function _fold_setup() internal {
        _vat_setUp();
        vat.file('ceil', 100 * RAD);
        vat.filk(i0, 'line', 100 * RAD);
    }

    modifier _fold_ { _fold_setup(); _; }

    function draw(bytes32 ilk, uint joy) internal {
        vat.file('ceil', joy * RAD + total_pool_rico * RAY);
        vat.filk(ilk, 'line', joy * RAD);
        feed.push(gtag, bytes32(RAY), block.timestamp + 1000);

        _slip(gem, me, WAD);
        vat.drip(i0);
        vat.frob(ilk, me, int(WAD), int(joy * WAD));
    }

    function tab(bytes32 ilk, address _urn) internal view returns (uint) {
        uint art = _art(ilk, _urn);
        (,uint rack,,,,,,,,,,) = vat.ilks(ilk);
        return art * rack;
    }

    function test_fold() public _fold_ {
        (,,,,,,uint fee,,,,,) = vat.ilks(i0);
        assertEq(fee, RAY);
        draw(i0, 1);
        vat.filk(i0, 'fee', RAY * 21 / 20);
        assertEq(tab(i0, me), RAD);

        skip(1);
        uint mejoy0 = rico.balanceOf(me) * RAY; // rad
        vat.drip(i0);
        uint djoy = rico.balanceOf(me) * RAY - mejoy0;
        uint tol = RAD / 1000;

        uint actual = RAD * 21 / 20;
        assertGt(tab(i0, me), actual - tol);
        assertLt(tab(i0, me), actual + tol);

        actual = RAD / 20;
        assertGt(djoy, actual - tol);
        assertLt(djoy, actual + tol);
    }
}

contract DssFlipTest is DssJsTest {
    Usr gal;

    function _flip_setup() internal {
        gem.mint(me, 1000 * WAD);

        rico.mint(a, 200 * WAD);
        rico.mint(b, 200 * WAD);

        curb(address(gem), UINT256_MAX, WAD, block.timestamp, 1);
        gal = cat;
    }

    modifier _flip_ { _flip_setup(); _; }

    function test_kick() public _flip_ {
        // no grab, no bill
        flow.flow(address(gem), 100 * WAD, address(rico), UINT256_MAX);
    }

    // testFail_tend_empty
    // test_tend
    // test_tend_later
    // test_dent
    // test_dent_same_bidder
    // test_beg
    // test_deal
    // test_tick
    //   N/A rico has no auction, immediately trades with balancer

    // test_yank_tend
    // test_yank_dent
    //   N/A rico has no auction, immediately trades with balancer, no shutdown (dss yank is for shutdown) (todo not anymore...)

    // test_no_deal_after_end
    //   N/A rico currently has no end
}


contract DssFlapTest is DssJsTest {

    uint nrefunds;
    function flowback(bytes32, address, uint refund) external {
        if (refund > 0) {
            nrefunds++;
        }
    }

    function _flap_setup() internal {
        rico.mint(me, 1000 * WAD);

        gem.mint(me, 1000 * WAD);
        gem.transfer(a, 200 * WAD);
        gem.transfer(b, 200 * WAD);
        // setOwner N/A, don't need to ward non-risk/rico gems
        gem.ward(me, false);
    }

    modifier _flap_ { _flap_setup(); _; }

    function test_kick() public _flap_ {
        assertEq(rico.balanceOf(me), 1000 * WAD);
        assertEq(rico.balanceOf(address(flow)), 0);
        assertEq(flow.count(), 0); // dss flap.fill() == 0

        flow.flow(address(rico), 100 * WAD, address(risk), 100000000000000000000 * WAD);
        assertEq(risk.balanceOf(me), 0);
        assertEq(rico.balanceOf(me), 900 * WAD);
        assertEq(rico.balanceOf(address(flow)), 100 * WAD);
        assertEq(rico.balanceOf(address(vow)), 0);
    }

    // testFail_tend_empty
    // test_tend
    // test_tend_dent_same_bidder
    // test_beg
    // test_tick
    //   N/A rico has standing auction mechanism, immediately trades with balancer (todo not anymore...)
}


contract DssFlopTest is DssJsTest {
    Usr gal;

    function _flop_setup() internal {
        rico.mint(me, 1000 * WAD);
        _gift(a, 200 * WAD);
        _gift(b, 200 * WAD);
    }

    modifier _flop_ { _flop_setup(); _; }

    function test_kick() public _flop_ {
        risk.mint(me, 100 * WAD);

        assertEq(risk.balanceOf(me), 100 * WAD);
        assertEq(rico.balanceOf(me), 600 * WAD);
        flow.flow(address(risk), 100 * WAD, address(rico), 10000000000000 * WAD);
        assertEq(risk.balanceOf(me), 0);
        assertEq(rico.balanceOf(me), 600 * WAD);

        (address v, address hag, uint ham, address wag, uint wam)
            = flow.auctions(bytes32(flow.count()));

        assertEq(v, me);
        assertEq(hag, address(risk));
        assertEq(ham, 100 * WAD);
        assertEq(wag, address(rico));
        assertEq(wam, 10000000000000 * WAD);
    }

    // test_dent
    // test_dent_Ash_less_than_bid
    // test_dent_same_bidder
    // test_tick
    //   N/A rico has standing auction mechanism, immediately trades with balancer (todo not anymore...)


    // test_no_deal_after_end
    //   N/A rico currently has no end

    // test_yank
    // test_yank_no_bids
    //   N/A rico has no auction, immediately trades with balancer, no shutdown (dss yank is for shutdown) (todo not anymore...)
}

contract DssClipTest is DssJsTest {
    Usr gal;

    function _clip_setup() internal {
        goldprice = 5 * RAY;
        rico_gemrico = gembal * (goldprice * 11 / 10) / RAY;
        total_pool_rico = rico_gemrico + rico_riskrico;

        gold.mint(me, gembal);
        rico.mint(me, rico_gemrico);
        Asset memory gold_rico_asset = Asset(address(gold), 5 * WAD / 10, gembal);
        Asset memory rico_gold_asset = Asset(address(rico), 5 * WAD / 10, rico_gemrico);
        PoolArgs memory gold_rico_args = PoolArgs(gold_rico_asset, rico_gold_asset, "mock", "MOCK", WAD / 100);

        pool_id_gold_rico = create_and_join_pool(gold_rico_args);
        flow.setPool(address(gem), address(rico), pool_id_gold_rico);


        // vault already has a bunch of rico (dai) and gem (gold)...skip transfers
        // rico (dai) already wards port (DaiJoin)
        // rico has no dog, accounts interact with vow directly
        // already have i0, no need to init ilk

        _slip(gold, me, 1000 * WAD);
        // no need to join

        vat.filk(i0, 'liqr', RAY / 2); // dss mat (rico uses inverse)

        feed.push(gtag, bytes32(goldprice), block.timestamp + 1000);

        vat.filk(i0, 'dust', 20 * RAD);
        vat.filk(i0, 'line', 10000 * RAD);
        vat.file('ceil', (10000 + total_pool_rico) * RAD); // rico has balancer pools, dss doesn't

        vat.filk(i0, 'chop', 11 * RAY / 10); // dss uses wad, rico uses ray
        // hole, Hole N/A (similar to cat.box), no rico equivalent, rico bails entire urn
        // dss clipper <-> rico flower (flip)

        assertEq(gold.balanceOf(me), 1000 * WAD);
        assertEq(rico.balanceOf(me), 0);
        vat.frob(i0, me, int(40 * WAD), int(100 * WAD));
        assertEq(gold.balanceOf(me), (1000 - 40) * WAD);
        assertEq(rico.balanceOf(me), 100 * WAD);

        feed.push(gtag, bytes32(4 * RAY), block.timestamp + 1000); // now unsafe

        // dss me/ali/bob hope clip N/A, rico vat wards vow

        rico.mint(me, 1000 * WAD);
        rico.mint(a, 1000 * WAD);
        rico.mint(b, 1000 * WAD);

        curb(address(gold), UINT256_MAX, WAD, block.timestamp, 1);
    }

    modifier _clip_ { _clip_setup(); _; }

    // test_change_dog
    //   N/A rico flow has per-auction vow (dss dog)

    // test_get_chop
    //   N/A rico has no dss chop function equivalent, just uses vat.ilks

    function test_kick() public _clip_ {
        // tip, chip N/A, rico currently has no keeper reward

        // clip.kicks() N/A rico flow doesn't count flips
        // clip.sales() N/A rico flow doesn't store sale information

        assertEq(gold.balanceOf(me), (1000 - 40) * WAD);
        assertEq(rico.balanceOf(a), 1000 * WAD);
        (uint ink, uint art) = vat.urns(i0, me);
        assertEq(ink, 40 * WAD);
        assertEq(art, 100 * WAD);

        ali.bail(i0, me); // no keeper arg
        bytes32 aid = bytes32(flow.count());
        vm.expectRevert(BalancerFlower.ErrSwapFail.selector);
        flow.glug(aid);

        // clip.kicks() N/A rico flow doesn't count flips
        // clip.sales() N/A rico flow doesn't store sale information

        (ink, art) = vat.urns(i0, me);
        assertEq(ink, 0);
        assertEq(art, 0);


        // Spot = $2.5
        feed.push(gtag, bytes32(goldprice), block.timestamp + 1000); // dss pip.poke

        skip(100);
        vat.frob(i0, me, int(40 * WAD), int(100 * WAD)); // dss pip.poke

        // Spot = $2
        feed.push(gtag, bytes32(4 * RAY), block.timestamp + 1000); /// dss spot.poke, now unsafe

        // clip.sales N/A

        assertEq(gold.balanceOf(me), (1000 - 80) * WAD);
        // buf N/A rico has no standing auction
        // tip, chip N/A

        assertEq(rico.balanceOf(b), 1000 * WAD);

        (ink, art) = vat.urns(i0, me);
        bob.bail(i0, me);
        flow.glug(bytes32(flow.count()));
        // clip.kicks() N/A rico flow doesn't count flips
        // clip.sales() N/A rico flow doesn't store sale information

        assertEq(gold.balanceOf(me), (1000 - 80) * WAD);
        (ink, art) = vat.urns(i0, me);
        // dss ink was 0, but rico auctions have flowback
        assertRange(ink, 110 * WAD * RAY / (goldprice * 11 / 10), WAD / 50);
        assertEq(art, 0);

        assertEq(rico.balanceOf(b), 1000 * WAD); // dss has bailer rewards, rico bark doesn't
    }

    function testFail_kick_zero_price() public _clip_ {
        feed.push(gtag, bytes32(0), UINT256_MAX);
        vm.expectRevert(); // todo need error types for zero cases
        vow.bail(i0, me);
    }

    // testFail_redo_zero_price
    //   N/A rico has no auction (todo now it does...)

    function test_kick_basic() public _clip_ {
        vow.bail(i0, me);
    }

    function test_kick_zero_tab() public _clip_ {
        (,uint art) = vat.urns(i0, me);
        // rico doesn't have kick() or a way to specify tab in bail
        // but tab == 0 if art == 0
        vat.frob(i0, me, 0, -int(art));
        (,art) = vat.urns(i0, me);
        assertEq(art, 0);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(i0, me);
    }

//    function test_kick_zero_lot() public _clip_ {
//        // but cut == 0 if ink == 0
//        // TODO curb_ramp handle undefined?
//        // vel/rel similar to dss lot
//        curb(address(gem), 0, WAD, block.timestamp, 1);
//        vm.expectRevert(); // todo need error types for zero cases
//        vow.bail(i0, me);
//    }
}