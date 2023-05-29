// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import { Gem } from '../lib/gemfab/src/gem.sol';
import { Ward } from '../lib/feedbase/src/mixin/ward.sol';
import { Ball } from '../src/ball.sol';
import { Vat } from '../src/vat.sol';
import { Vow } from '../src/vow.sol';
import { RicoSetUp, WethLike, Guy } from "./RicoHelper.sol";
import { Asset, PoolArgs } from "./UniHelper.sol";
import { Math } from '../src/mixin/math.sol';
import { Hook } from '../src/hook/hook.sol';
import { ERC20Hook, NO_CUT } from '../src/hook/ERC20hook.sol';

// integrated vow/flow tests
contract VowTest is Test, RicoSetUp {
    uint256 public init_join = 1000;
    uint stack = WAD * 10;
    bytes32[] ilks;
    address rico_risk_pool;
    uint back_count;

    function setUp() public {
        make_bank();
        init_gold();
        ilks.push(gilk);
        rico.approve(address(hook), type(uint256).max);

        vow.file('vel', 1e18);
        vow.file('rel', 1e12);
        vow.file('bel', 0);
        vow.file('cel', 600);

        // have 10k each of rico, risk and gold
        gold.approve(router, type(uint256).max);
        rico.approve(router, type(uint256).max);
        risk.approve(router, type(uint256).max);
        gold.approve(address(hook), type(uint256).max);
        rico.approve(address(hook), type(uint256).max);
        risk.approve(address(hook), type(uint256).max);

        rico_risk_pool = getPoolAddr(arico, arisk, 3000);
        rico_mint(2000 * WAD, true);
        risk.mint(self, 100000 * WAD);
        PoolArgs memory rico_risk_args = getArgs(arico, 1000 * WAD, arisk, 1000 * WAD, 3000, x96(1));
        join_pool(rico_risk_args);

        PoolArgs memory gold_rico_args = getArgs(agold, 1000 * WAD, arico, 1000 * WAD, 3000, x96(1));
        create_and_join_pool(gold_rico_args);

        guy = new Guy(avat, avow);
    }

    function test_flap_price() public {
        uint borrow = WAD;
        uint rico_price_in_risk = 10;
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        feedpush(RICO_RISK_TAG, bytes32(rico_price_in_risk * RAY), type(uint).max);
        vat.frob(gilk, self, abi.encodePacked(WAD), int(borrow));
        skip(BANKYEAR);
        vow.drip(gilk);

        uint surplus = rico.balanceOf(avow);
        (,uint rack,,,,,,,) = vat.ilks(gilk);
        assertClose(surplus, rmul(rack, borrow) - borrow, 1_000_000_000);

        // cancel out any sin so only rico needs to be considered
        uint sin_wad = vat.sin(avow) / RAY;
        rico_mint(sin_wad, false);
        rico.transfer(avow, sin_wad);

        uint debt = vat.debt();
        uint rush = wdiv((surplus + debt), debt);
        uint expected_risk_cost = wdiv(surplus * rico_price_in_risk, rush);

        risk.mint(self, WAD * 1_000);
        risk.approve(address(hook), type(uint).max);
        uint self_rico_1 = rico.balanceOf(self);
        uint self_risk_1 = risk.balanceOf(self);

        vow.keep(ilks);

        uint rico_gain = rico.balanceOf(self) - self_rico_1;
        uint risk_cost = self_risk_1 - risk.balanceOf(self);

        assertClose(expected_risk_cost, risk_cost, 10_000);
        assertEq(rico_gain, surplus);
    }

    function test_flop_price() public {
        uint borrow = WAD * 1000;
        uint risk_price_in_rico = 10;
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        feedpush(RISK_RICO_TAG, bytes32(risk_price_in_rico * RAY), type(uint).max);
        vat.frob(gilk, self, abi.encodePacked(WAD), int(borrow));

        uint debt = vat.debt();
        uint sin  = vat.sin(avow) / RAY;
        uint rush = wdiv((sin + debt), debt);
        uint expected_rico_per_risk = wdiv(risk_price_in_rico, rush);

        rico.approve(address(hook), type(uint).max);
        uint self_rico_1 = rico.balanceOf(self);
        uint self_risk_1 = risk.balanceOf(self);

        vow.keep(ilks);

        uint rico_cost = self_rico_1 - rico.balanceOf(self);
        uint risk_gain = risk.balanceOf(self) - self_risk_1;
        assertEq(rico_cost / risk_gain, expected_rico_per_risk);
    }

    function test_bail_price() public {
        // frob to edge of safety
        uint borrow = WAD * 1000;
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        vat.frob(gilk, self, abi.encodePacked(WAD), int(borrow));

        // drop gold/rico to 75%
        feedpush(grtag, bytes32(750 * RAY), type(uint).max);
        // price should be 0.75**2, as 0.75 for oracle drop and 0.75 for rush factor
        uint expected = wmul(borrow, wmul(WAD * 75 / 100, WAD * 75 / 100));
        rico.mint(address(guy), expected);
        guy.approve(address(rico), ahook, expected);
        guy.bail(gilk, self);

        // guy was given exact amount, check all was spent for all gold deposit
        assertEq(rico.balanceOf(address(guy)), uint(0));
        assertEq(gold.balanceOf(address(guy)), WAD);
    }

    function test_bail_refund() public {
        // set c ratio to double
        vat.filk(gilk, "liqr", RAY * 2);
        uint borrow = WAD * 500;
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        // frob to edge of safety
        vat.frob(gilk, self, abi.encodePacked(WAD), int(borrow));

        // drop gold/rico to 75%
        feedpush(grtag, bytes32(750 * RAY), type(uint).max);
        // position is still overcollateralized, should get a refund and guy should only pay borrowed rico
        rico.mint(address(guy), borrow);
        guy.approve(address(rico), ahook, borrow);
        // price should be 0.75**2, as 0.75 for oracle drop and 0.75 for rush factor
        guy.bail(gilk, self);

        // guy should not get all gold, should be ink * (amount borrowed / expected price for full collateral and rush)
        // price should be 0.75**2, as 0.75 for oracle drop and 0.75 for rush factor
        uint expected_full = wmul(borrow * 2, wmul(WAD * 75 / 100, WAD * 75 / 100));
        uint guy_earn = wmul(WAD, wdiv(borrow, expected_full));
        assertEq(gold.balanceOf(address(guy)), guy_earn);

        // as self urn was overcollateralized not all ink should have been taken, check corract amount still there
        uint ink_left = hook.inks(gilk, self);
        assertEq(ink_left, WAD - guy_earn);
    }

    function test_keep_deficit_gas() public {
        feedpush(grtag, bytes32(1000 * RAY), block.timestamp + 1000);
        vat.frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        feedpush(grtag, bytes32(RAY * 0), block.timestamp + 1000);
        vow.bail(gilk, self);

        bytes32[] memory gilks = new bytes32[](2);
        gilks[0] = gilk;
        gilks[1] = gilk;
        rico_mint(100 * WAD, false);
        uint gas = gasleft();
        vow.keep(gilks);
        check_gas(gas, 140055);
    }

    function test_keep_surplus_gas() public {
        vat.filk(gilk, 'fee', 2 * RAY);
        feedpush(grtag, bytes32(10000 * RAY), block.timestamp + 1000);
        vat.frob(gilk, self, abi.encodePacked(WAD), int(3000 * WAD));
        skip(1);

        bytes32[] memory gilks = new bytes32[](2);
        gilks[0] = gilk;
        gilks[1] = gilk;
        uint gas = gasleft();
        vow.keep(gilks);
        check_gas(gas, 140137);
    }

    function test_bail_gas() public {
        feedpush(grtag, bytes32(1000 * RAY), block.timestamp + 1000);
        vat.frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        feedpush(grtag, bytes32(0), block.timestamp + 1000);
        uint gas = gasleft();
        vow.bail(gilk, self);
        check_gas(gas, 56435);
    }

    // goldusd, par, and liqr all = 1 after setup
    function test_risk_ramp_is_used() public {
        // art == 10 * ink
        feedpush(grtag, bytes32(RAY * 1000), block.timestamp + 1000);
        vat.frob(gilk, address(this), abi.encodePacked(1000 * WAD), int(10000 * WAD));
 
        // set rate of risk sales to near zero
        // set mint ramp higher to use risk ramp
        vow.file('vel', WAD);
        vow.file('rel', WAD);
        vow.file('bel', block.timestamp - 1);
        vow.file('cel', 1);

        // setup frobbed to edge, dropping gold price puts system way underwater
        feedpush(grtag, bytes32(RAY), block.timestamp + 10000);

        // create the sin and kick off risk sale
        uint supply = risk.totalSupply();
        vm.expectCall(avat, abi.encodePacked(Vat.grab.selector));
        vow.bail(gilk, self);
        feedpush(RISK_RICO_TAG, bytes32(10000 * RAY), block.timestamp + 1000);
        vm.expectCall(ahook, abi.encodePacked(ERC20Hook.grabhook.selector));
        vow.keep(ilks);
        assertEq(risk.totalSupply(), supply + WAD);

        rico_mint(10000 * WAD, true);
        rico.transfer(address(guy), 10000 * WAD);
        guy.approve(arico, ahook, UINT256_MAX);

        rico_mint(10000 * WAD, true);
        rico.transfer(address(guy), 10000 * WAD);
        uint vowrisk = risk.balanceOf(avow);

        // vow flow.flow'd for max possible - should receive nothing back
        assertEq(risk.balanceOf(avow), vowrisk);
    }

    function test_wards() public {
        vow.file('vel', WAD);
        vow.link('flow', address(hook));

        vow.give(address(0));
        hook.give(address(0));

        vm.expectRevert(abi.encodeWithSelector(
            Ward.ErrWard.selector, self, avow, Vow.file.selector
        ));
        vow.file('vel', WAD);
        vm.expectRevert(abi.encodeWithSelector(
            Ward.ErrWard.selector, self, avow, Vow.link.selector
        ));
        vow.link('flow', address(hook));

        rico_mint(100 * WAD, false);
        vow.keep(ilks);
        vat.frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(gilk, self);
    }

    function test_drip() public {
        (,,,,,uint rho,,,) = vat.ilks(gilk);
        assertEq(rho, block.timestamp);
        assertEq(rico.balanceOf(self), 0);

        vat.filk(gilk, 'fee', 2 * RAY);
        feedpush(grtag, bytes32(RAY * 1000), type(uint).max);
        vat.frob(gilk, address(this), abi.encodePacked(WAD), int(WAD));
        uint firstrico = rico.balanceOf(self);
        rico_mint(1, false); // vat burns 1 extra to round in system's favor
        vat.frob(gilk, address(this), abi.encodePacked(-int(WAD)), -int(WAD));

        skip(1);
        // can only mint a wad rico for a wad gold
        vat.frob(gilk, address(this), abi.encodePacked(WAD), int(WAD));
        assertEq(rico.balanceOf(self), firstrico);
        rico_mint(1, false);
        vat.frob(gilk, address(this), abi.encodePacked(-int(WAD)), -int(WAD));

        // until drip, then can mint more
        vow.drip(gilk);
        assertEq(rico.balanceOf(self), 0);
        vat.frob(gilk, address(this), abi.encodePacked(WAD), int(WAD));
        assertEq(rico.balanceOf(self), firstrico * 2);
    }

    function test_keep_balanced() public {
        vat.filk(gilk, 'fee', 2 * RAY);

        feedpush(grtag, bytes32(RAY * 1000), block.timestamp + 1000);
        uint amt = vat.sin(avow) / RAY;
        vat.frob(gilk, address(this), abi.encodePacked(amt), int(amt));
        skip(1);

        feedpush(grtag, bytes32(0), block.timestamp + 10000);

        assertEq(rico.balanceOf(avow), 0);
        vow.keep(ilks);
        assertEq(rico.balanceOf(avow), vat.sin(avow) / RAY);
    }

    function test_keep_unbalanced_slightly_more_rico() public {
        vat.filk(gilk, 'fee', 2 * RAY);

        feedpush(grtag, bytes32(RAY * 1000), block.timestamp + 1000);
        uint amt = vat.sin(avow) / RAY + 1;
        vat.frob(gilk, address(this), abi.encodePacked(amt), int(amt));
        skip(1);

        feedpush(grtag, bytes32(0), block.timestamp + 10000);

        feedpush(RICO_RISK_TAG, bytes32(1000 * RAY), UINT256_MAX);
        assertEq(rico.balanceOf(avow), 0);
        uint self_risk_1 = risk.balanceOf(self);
        vow.keep(ilks);
        uint self_risk_2 = risk.balanceOf(self);
        assertEq(rico.balanceOf(avow), 1);
        assertGt(self_risk_1, self_risk_2);
    }

    function test_keep_unbalanced_slightly_more_sin() public {
        vat.filk(gilk, 'fee', 2 * RAY);

        feedpush(grtag, bytes32(RAY * 1000), block.timestamp + 1000);
        uint amt = vat.sin(avow) / RAY - 1;
        vat.frob(gilk, address(this), abi.encodePacked(amt), int(amt));
        skip(1);

        feedpush(grtag, bytes32(0), block.timestamp + 10000);

        assertEq(rico.balanceOf(avow), 0);
        (uint vel, uint rel, uint bel, uint cel) = vow.ramp();
        uint flop = min(wmul(rel, risk.totalSupply()), vel) * min(block.timestamp - bel, cel);
        feedpush(RISK_RICO_TAG, bytes32(RAY), block.timestamp + 1000);
        uint risk_ts1 = risk.totalSupply();
        vow.keep(ilks);
        uint risk_ts2 = risk.totalSupply();
        assertGt(rico.balanceOf(avow), 1);
        assertEq(vat.sin(avow), 2 * RAY);
        assertEq(risk_ts2, risk_ts1 + flop);
    }

    function test_bail_hook() public {
        FrobHook hook = new FrobHook();
        vat.filk(gilk, 'hook', uint(bytes32(bytes20(address(hook)))));
        vat.frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        uint vowgoldbefore = gold.balanceOf(avow);

        ZeroHook zhook = new ZeroHook();
        vat.filk(gilk, 'hook', uint(bytes32(bytes20(address(zhook)))));
        vm.expectCall(address(zhook), abi.encodePacked(zhook.grabhook.selector));
        vow.bail(gilk, self);
        assertEq(gold.balanceOf(avow), vowgoldbefore);
    }
}

contract FrobHook is Hook {
    function frobhook(
        address , bytes32 , address , bytes calldata dink, int dart
    ) external pure returns (bool safer){
        return int(uint(bytes32(dink[:32]))) >= 0 && dart <= 0; 
    }
    function grabhook(
        address vow, bytes32 i, address u, uint art, uint bill, address keeper, uint rush, uint cut
    ) external {}
    function safehook(
        bytes32 , address
    ) external pure returns (uint, uint){return(uint(10 ** 18 * 10 ** 27), type(uint256).max);}
}
contract ZeroHook is Hook {
    function frobhook(
        address sender, bytes32 i, address u, bytes calldata dink, int dart
    ) external returns (bool safer) {}
    function grabhook(
        address vow, bytes32 i, address u, uint art, uint bill, address keeper, uint rush, uint cut
    ) external {}
    function safehook(
        bytes32 , address
    ) external pure returns (uint, uint){return(uint(0), type(uint256).max);}
}

contract Usr {
    WethLike weth;
    Vat vat;
    constructor(Vat _vat, WethLike _weth) {
        weth = _weth;
        vat  = _vat;
    }
    function deposit() public payable {
        weth.deposit{value: msg.value}();
    }
    function approve(address usr, uint amt) public {
        weth.approve(usr, amt);
    }
    function frob(bytes32 ilk, address usr, bytes calldata dink, int dart) public {
        vat.frob(ilk, usr, dink, dart);
    }
    function transfer(address gem, address dst, uint amt) public {
        Gem(gem).transfer(dst, amt);
    }
}

contract VowJsTest is Test, RicoSetUp {
    // me == js ALI
    address me;
    Usr bob;
    Usr cat;
    address b;
    address c;
    address rico_risk_pool;
    WethLike weth;
    bytes32 i0;
    bytes32[] ilks;

    function setUp() public {
        make_bank();
        init_dai();
        init_gold();
        weth = WethLike(WETH);
        me = address(this);
        bob = new Usr(vat, weth);
        cat = new Usr(vat, weth);
        b = address(bob);
        c = address(cat);
        i0 = wilk;
        ilks.push(i0);

        weth.deposit{value: 6000 * WAD}();
        risk.mint(me, 10000 * WAD);
        weth.approve(address(hook), UINT256_MAX);

        vat.file('ceil', 10000 * RAD);
        vat.filk(i0, 'line', 10000 * RAD);
        vat.filk(i0, 'chop', RAY * 11 / 10);

        vow.file('vel', WAD);
        vow.file('rel', WAD / 10000);
        vow.file('bel', 0);
        vow.file('cel', 60);

        feedpush(wrtag, bytes32(RAY), block.timestamp + 2 * BANKYEAR);
        feedpush(grtag, bytes32(RAY), block.timestamp + 2 * BANKYEAR);
        uint fee = 1000000001546067052200000000; // == ray(1.05 ** (1/BANKYEAR))
        vat.filk(i0, 'fee', fee);
        vat.frob(i0, me, abi.encodePacked(100 * WAD), 0);
        vat.frob(i0, me, abi.encodePacked(int(0)), int(99 * WAD));

        uint bal = rico.balanceOf(me);
        assertEq(bal, 99 * WAD);
        (Vat.Spot safe1,,) = vat.safe(i0, me);
        assertEq(uint(safe1), uint(Vat.Spot.Safe));

        cat.deposit{value: 7000 * WAD}();
        cat.approve(address(hook), UINT256_MAX);
        cat.frob(i0, c, abi.encodePacked(4001 * WAD), int(4000 * WAD));
        cat.transfer(arico, me, 4000 * WAD);

        weth.approve(address(router), UINT256_MAX);
        rico.approve(address(router), UINT256_MAX);
        risk.approve(address(router), UINT256_MAX);
        dai.approve(address(router), UINT256_MAX);
        weth.approve(ahook, UINT256_MAX);
        rico.approve(ahook, UINT256_MAX);
        risk.approve(ahook, UINT256_MAX);
        dai.approve(ahook, UINT256_MAX);

        PoolArgs memory dai_rico_args = getArgs(DAI, 2000 * WAD, arico, 2000 * WAD, 500, x96(1));
        join_pool(dai_rico_args);

        PoolArgs memory risk_rico_args = getArgs(arisk, 2000 * WAD, arico, 2000 * WAD, 3000, x96(1));
        join_pool(risk_rico_args);
        rico_risk_pool = getPoolAddr(arisk, arico, 3000);
        
        vow.file('vel', 200 * WAD);
        vow.file('rel', WAD);
        vow.file('bel', block.timestamp);
        vow.file('cel', 1);
        guy = new Guy(avat, avow);
    }

    function test_bail_urns_1yr_unsafe() public {
        // wait a year, flap the surplus
        skip(BANKYEAR);
        uint start_ink = _ink(i0, me);
        feedpush(RICO_RISK_TAG, bytes32(RAY), UINT256_MAX);
        vow.keep(ilks);

        (Vat.Spot spot,,) = vat.safe(i0, me);
        assertEq(uint(spot), uint(Vat.Spot.Sunk));

        // should be balanced
        uint sin0 = vat.sin(avow);
        uint vow_rico0 = rico.balanceOf(avow);
        assertEq(sin0 / RAY, 0);
        assertEq(vow_rico0, 0);

        // bail the urn frobbed in setup
        rico_mint(1000 * WAD, false);
        rico.transfer(address(guy), 1000 * WAD);
        guy.approve(arico, ahook, UINT256_MAX);
        vm.expectCall(address(hook), abi.encodePacked(ERC20Hook.grabhook.selector));
        vow.bail(i0, me);
        // urn should be grabbed
        uint ink = _ink(i0, me); uint art = _art(i0, me);
        assertEq(art, 0);
        assertLt(ink, start_ink);

        uint sin1 = vat.sin(avow);
        uint vow_rico1 = rico.balanceOf(avow);
        assertEq(art, 0);
        assertGt(sin1, 0);
        assertGt(vow_rico1, 0);
    }

    function test_bail_urns_when_safe() public {
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(i0, me);

        uint sin0 = vat.sin(avow);
        assertEq(sin0 / RAY, 0);

        skip(BANKYEAR);
        vm.expectCall(address(hook), abi.encodePacked(hook.grabhook.selector));
        vow.bail(i0, me);
        vm.expectRevert(Vow.ErrSafeBail.selector);
        vow.bail(i0, me);
    }

    function test_keep_vow_1yr_drip_flap() public {
        uint initial_total = rico.totalSupply();
        skip(BANKYEAR);
        feedpush(RICO_RISK_TAG, bytes32(RAY), UINT256_MAX);
        vm.expectCall(address(hook), abi.encodePacked(hook.flow.selector));
        vow.keep(ilks);
        uint final_total = rico.totalSupply();
        assertGt(final_total, initial_total);
        // minted 4099, fee is 1.05. 0.05*4099 as no surplus buffer
        assertGe(final_total - initial_total, 204.94e18);
        assertLe(final_total - initial_total, 204.96e18);
    }

    function test_keep_vow_1yr_drip_flop() public {
        // wait a year, bail the existing urns
        // bails should leave more sin than rico dripped
        skip(BANKYEAR);
        vm.expectCall(address(hook), abi.encodePacked(hook.grabhook.selector));
        vow.bail(i0, me);
        rico_mint(WAD * 5000, false);
        vow.bail(i0, address(cat));

        // more sin than rico, should flop
        feedpush(RISK_RICO_TAG, bytes32(RAY), UINT256_MAX);
        vm.expectCall(avat, abi.encodePacked(Vat.heal.selector));
        vm.expectCall(address(hook), abi.encodePacked(hook.flow.selector));
        vow.keep(ilks);
    }

    function test_keep_rate_limiting_flop_absolute_rate() public {
        vat.file('ceil', 100000 * RAD);
        vat.filk(i0, 'line', 100000 * RAD);
        vow.file('vel', WAD);
        vow.file('rel', WAD);
        vow.file('bel', block.timestamp - 1);
        vow.file('cel', 1);

        assertGt(risk.totalSupply(), WAD);
        prepguyrico(10000 * WAD, true);
        vow.keep(ilks);
    }

    function test_keep_rate_limiting_flop_relative_rate() public {
        vat.file('ceil', 100000 * RAD);
        vat.filk(i0, 'line', 100000 * RAD);
        vow.file('rel', WAD);
        vow.file('vel', risk.totalSupply() * 2);
        vow.file('bel', block.timestamp - 1);
        vow.file('cel', 1);

        assertGt(risk.totalSupply(), WAD);
        uint risksupply = risk.totalSupply();
        prepguyrico(10000 * WAD, true);
        guy.keep(ilks);
        assertEq(risk.totalSupply(), risksupply + risksupply);
    }

    function test_e2e_all_actions() public {
        // run a flap and ensure risk is burnt
        uint risk_initial_supply = risk.totalSupply();
        skip(BANKYEAR);
        feedpush(RICO_RISK_TAG, bytes32(2 * RAY), UINT256_MAX);
        risk.mint(address(guy), 1000 * WAD);
        guy.approve(arisk, ahook, UINT256_MAX);
        guy.keep(ilks);

        skip(60);
        feedpush(RICO_RISK_TAG, bytes32(10000 * RAY), UINT256_MAX);
        risk.mint(address(guy), 1000 * WAD);
        vm.expectCall(address(hook), abi.encodePacked(hook.flow.selector));
        vow.keep(ilks); // call again to burn risk given to vow the first time

        uint risk_post_flap_supply = risk.totalSupply();
        assertLt(risk_post_flap_supply, risk_initial_supply + 1000 * WAD * 2);

        // confirm bail trades the weth for rico
        uint vow_rico_0 = rico.balanceOf(avow);
        uint hook_weth_0 = weth.balanceOf(address(hook));
        vm.expectCall(address(hook), abi.encodePacked(hook.grabhook.selector));
        vow.bail(i0, me);

        uint vow_pre_flop_rico = rico.balanceOf(avow);
        feedpush(RISK_RICO_TAG, bytes32(10 * RAY), UINT256_MAX);
        prepguyrico(2000 * WAD, false);
        vm.expectCall(address(hook), abi.encodePacked(hook.flow.selector));
        guy.keep(ilks);

        // now vow should hold more rico
        uint vow_post_flop_rico = rico.balanceOf(avow);
        assertGt(vow_post_flop_rico, vow_pre_flop_rico);

        // now complete the liquidation
        feedpush(wrtag, bytes32(100 * RAY), UINT256_MAX);
        uint vow_rico_1 = rico.balanceOf(avow);
        uint vat_weth_1 = weth.balanceOf(address(hook));
        assertGt(vow_rico_1, vow_rico_0);
        assertLt(vat_weth_1, hook_weth_0);
    }
}

