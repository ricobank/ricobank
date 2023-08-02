// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

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
import { ERC20Hook } from '../src/hook/ERC20hook.sol';
import {File} from '../src/file.sol';
import {Bank} from '../src/bank.sol';

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
        rico.approve(bank, type(uint256).max);

        File(bank).file('vel', bytes32(uint(1e18)));
        File(bank).file('rel', bytes32(uint(1e12)));
        File(bank).file('bel', bytes32(uint(0)));
        File(bank).file('cel', bytes32(uint(600)));

        // have 10k each of rico, risk and gold
        gold.approve(router, type(uint256).max);
        rico.approve(router, type(uint256).max);
        risk.approve(router, type(uint256).max);
        gold.approve(bank, type(uint256).max);
        rico.approve(bank, type(uint256).max);
        risk.approve(bank, type(uint256).max);

        rico_risk_pool = getPoolAddr(arico, arisk, 3000);
        rico_mint(2000 * WAD, true);
        risk.mint(self, 100000 * WAD);
        PoolArgs memory rico_risk_args = getArgs(arico, 1000 * WAD, arisk, 1000 * WAD, 3000, x96(1));
        join_pool(rico_risk_args);

        PoolArgs memory gold_rico_args = getArgs(agold, 1000 * WAD, arico, 1000 * WAD, 3000, x96(1));
        create_and_join_pool(gold_rico_args);

        guy = new Guy(bank);
    }

    function test_flap_price() public {
        uint borrow = WAD;
        uint rico_price_in_risk = 10;
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        feedpush(RICO_RISK_TAG, bytes32(rico_price_in_risk * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(borrow));
        skip(BANKYEAR);
        Vat(bank).drip(gilk);

        uint surplus = rico.balanceOf(bank);
        uint rack = Vat(bank).ilks(gilk).rack;
        assertClose(surplus, rmul(rack, borrow) - borrow, 1_000_000_000);

        // cancel out any sin so only rico needs to be considered
        uint sin_wad = Vat(bank).sin() / RAY;
        rico_mint(sin_wad, false);
        rico.transfer(bank, sin_wad);

        // set pep to * 1000 growth rate
        File(bank).file('flappep', bytes32(RAY * 1000));
        // set pop to increase initial price by 1%
        File(bank).file('flappop', bytes32(RAY * 99 / 100));

        uint debt = Vat(bank).debt() - sin_wad;
        uint gain = surplus * 1000;
        uint init = debt * 99 / 100;

        uint rush = wdiv((gain + init), debt);
        // (50 + 2101.05 * 0.99) / 2101.05 = 1.013_797_624_9970253
        assertClose(rush, WAD * 1_013_797_624 / 1_000_000_000, 100_000);

        uint expected_risk_cost = wdiv(surplus * rico_price_in_risk, rush);

        risk.mint(self, WAD * 1_000);
        risk.approve(bank, type(uint).max);
        uint self_rico_1 = rico.balanceOf(self);
        uint self_risk_1 = risk.balanceOf(self);

        Vow(bank).keep(ilks);

        uint rico_gain = rico.balanceOf(self) - self_rico_1;
        uint risk_cost = self_risk_1 - risk.balanceOf(self);

        assertClose(expected_risk_cost, risk_cost, 10_000);
        assertEq(rico_gain, surplus);
    }

    function test_flop_price() public {
        uint borrow = WAD * 10000;
        uint risk_price_in_rico = 10 * RAY;
        feedpush(grtag, bytes32(10000 * RAY), type(uint).max);
        feedpush(RISK_RICO_TAG, bytes32(risk_price_in_rico), type(uint).max);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(borrow));

        // set pep to *1000 rate discount increases
        File(bank).file('floppep', bytes32(RAY * 1000));
        // set pop so initial flop discount is about 1%
        File(bank).file('floppop', bytes32(RAY * 101 / 100));

        uint debt = Vat(bank).debt();
        uint sin  = Vat(bank).sin() / RAY;

        uint gain = sin * 1000;
        uint init = debt * 101 / 100;
        uint rush = wdiv((gain + init), debt);
        uint expected_rico_per_risk = wdiv(risk_price_in_rico, rush) / 10**9;

        rico.approve(bank, type(uint).max);
        uint self_rico_1 = rico.balanceOf(self);
        uint self_risk_1 = risk.balanceOf(self);

        Vow(bank).keep(ilks);

        uint rico_cost = self_rico_1 - rico.balanceOf(self);
        uint risk_gain = risk.balanceOf(self) - self_risk_1;

        assertEq(wdiv(rico_cost, risk_gain), expected_rico_per_risk);
    }

    function test_bail_price() public {
        // frob to edge of safety
        uint borrow = WAD * 1000;
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(borrow));

        // drop gold/rico to 75%
        feedpush(grtag, bytes32(750 * RAY), type(uint).max);
        // price should be 0.75**2, as 0.75 for oracle drop and 0.75 for rush factor
        uint expected = wmul(borrow, wmul(WAD * 75 / 100, WAD * 75 / 100));
        rico_mint(expected, false);
        rico.transfer(address(guy), expected);
        guy.approve(address(rico), bank, expected);
        bytes memory data = guy.bail(gilk, self);

        uint earn = uint(bytes32(data));

        // check returned bytes represent quantity of tokens received
        assertEq(earn, WAD);

        // guy was given exact amount, check all was spent for all gold deposit
        assertEq(rico.balanceOf(address(guy)), uint(0));
        assertEq(gold.balanceOf(address(guy)), WAD);
    }

    function test_bail_refund() public {
        // set c ratio to double
        Vat(bank).filk(gilk, "liqr", bytes32(RAY * 2));
        uint borrow = WAD * 500;
        feedpush(grtag, bytes32(1000 * RAY), type(uint).max);
        // frob to edge of safety
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(borrow));

        // drop gold/rico to 75%
        feedpush(grtag, bytes32(750 * RAY), type(uint).max);
        // position is still overcollateralized, should get a refund and guy should only pay borrowed rico
        rico_mint(borrow, false);
        rico.transfer(address(guy), borrow);
        guy.approve(address(rico), bank, borrow);
        // price should be 0.75**2, as 0.75 for oracle drop and 0.75 for rush factor
        guy.bail(gilk, self);

        // guy should not get all gold, should be ink * (amount borrowed / expected price for full collateral and rush)
        // price should be 0.75**2, as 0.75 for oracle drop and 0.75 for rush factor
        uint expected_full = wmul(borrow * 2, wmul(WAD * 75 / 100, WAD * 75 / 100));
        uint guy_earn = wmul(WAD, wdiv(borrow, expected_full));
        assertEq(gold.balanceOf(address(guy)), guy_earn);

        // as self urn was overcollateralized not all ink should have been taken, check corract amount still there
        uint ink_left = _ink(gilk, self);
        assertEq(ink_left, WAD - guy_earn);
    }

    function test_keep_deficit_gas() public {
        feedpush(grtag, bytes32(1000 * RAY), block.timestamp + 1000);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        feedpush(grtag, bytes32(RAY * 0), block.timestamp + 1000);
        Vat(bank).bail(gilk, self);

        bytes32[] memory gilks = new bytes32[](2);
        gilks[0] = gilk;
        gilks[1] = gilk;
        rico_mint(100 * WAD, false);
        uint gas = gasleft();
        Vow(bank).keep(gilks);
        check_gas(gas, 139036);
    }

    function test_keep_surplus_gas() public {
        Vat(bank).filk(gilk, 'fee', bytes32(2 * RAY));
        feedpush(grtag, bytes32(10000 * RAY), block.timestamp + 1000);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(3000 * WAD));
        skip(1);

        bytes32[] memory gilks = new bytes32[](2);
        gilks[0] = gilk;
        gilks[1] = gilk;
        uint gas = gasleft();
        Vow(bank).keep(gilks);
        check_gas(gas, 133640);
    }

    function test_bail_gas() public {
        feedpush(grtag, bytes32(1000 * RAY), block.timestamp + 1000);
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        feedpush(grtag, bytes32(0), block.timestamp + 1000);
        uint gas = gasleft();
        Vat(bank).bail(gilk, self);
        check_gas(gas, 46744);
    }

    // goldusd, par, and liqr all = 1 after setup
    function test_risk_ramp_is_used() public {
        // art == 10 * ink
        feedpush(grtag, bytes32(RAY * 1000), block.timestamp + 1000);
        Vat(bank).frob(gilk, address(this), abi.encodePacked(1000 * WAD), int(10000 * WAD));
 
        // set rate of risk sales to near zero
        // set mint ramp higher to use risk ramp
        File(bank).file('vel', bytes32(uint(WAD)));
        File(bank).file('rel', bytes32(uint(WAD)));
        File(bank).file('bel', bytes32(uint(block.timestamp - 1)));
        File(bank).file('cel', bytes32(uint(1)));

        // setup frobbed to edge, dropping gold price puts system way underwater
        feedpush(grtag, bytes32(RAY), block.timestamp + 10000);

        // create the sin and kick off risk sale
        uint supply = risk.totalSupply();
        vm.expectCall(bank, abi.encodePacked(Vat.bail.selector));
        Vat(bank).bail(gilk, self);
        feedpush(RISK_RICO_TAG, bytes32(10000 * RAY), block.timestamp + 1000);
        vm.expectCall(ahook, abi.encodePacked(ERC20Hook.bailhook.selector));
        Vow(bank).keep(ilks);
        assertEq(risk.totalSupply(), supply + WAD);

        rico_mint(10000 * WAD, true);
        rico.transfer(address(guy), 10000 * WAD);
        guy.approve(arico, bank, UINT256_MAX);

        rico_mint(10000 * WAD, true);
        rico.transfer(address(guy), 10000 * WAD);
        uint vowrisk = risk.balanceOf(bank);

        // vow flow.flow'd for max possible - should receive nothing back
        assertEq(risk.balanceOf(bank), vowrisk);
    }

    function test_drip() public {
        uint rho = Vat(bank).ilks(gilk).rho;
        assertEq(rho, block.timestamp);
        assertEq(rico.balanceOf(self), 0);

        Vat(bank).filk(gilk, 'fee', bytes32(2 * RAY));
        feedpush(grtag, bytes32(RAY * 1000), type(uint).max);
        Vat(bank).frob(gilk, address(this), abi.encodePacked(WAD), int(WAD));
        uint firstrico = rico.balanceOf(self);
        rico_mint(1, false); // vat burns 1 extra to round in system's favor
        Vat(bank).frob(gilk, address(this), abi.encodePacked(-int(WAD)), -int(WAD));

        skip(1);
        // can only mint a wad rico for a wad gold
        Vat(bank).frob(gilk, address(this), abi.encodePacked(WAD), int(WAD));
        assertEq(rico.balanceOf(self), firstrico);
        rico_mint(1, false);
        Vat(bank).frob(gilk, address(this), abi.encodePacked(-int(WAD)), -int(WAD));

        // until drip, then can mint more
        Vat(bank).drip(gilk);
        assertEq(rico.balanceOf(self), 0);
        Vat(bank).frob(gilk, address(this), abi.encodePacked(WAD), int(WAD));
        assertEq(rico.balanceOf(self), firstrico * 2);
    }

    function test_keep_balanced() public {
        Vat(bank).filk(gilk, 'fee', bytes32(2 * RAY));

        feedpush(grtag, bytes32(RAY * 1000), block.timestamp + 1000);
        uint amt = Vat(bank).sin() / RAY;
        Vat(bank).frob(gilk, address(this), abi.encodePacked(amt), int(amt));
        skip(1);

        feedpush(grtag, bytes32(0), block.timestamp + 10000);

        assertEq(rico.balanceOf(bank), 0);
        Vow(bank).keep(ilks);
        assertEq(rico.balanceOf(bank), Vat(bank).sin() / RAY);
    }

    function test_keep_unbalanced_slightly_more_rico() public {
        Vat(bank).filk(gilk, 'fee', bytes32(2 * RAY));

        feedpush(grtag, bytes32(RAY * 1000), block.timestamp + 1000);
        uint amt = Vat(bank).sin() / RAY + 1;
        Vat(bank).frob(gilk, address(this), abi.encodePacked(amt), int(amt));
        skip(1);

        feedpush(grtag, bytes32(0), block.timestamp + 10000);

        feedpush(RICO_RISK_TAG, bytes32(1000 * RAY), UINT256_MAX);
        assertEq(rico.balanceOf(bank), 0);
        uint self_risk_1 = risk.balanceOf(self);
        Vow(bank).keep(ilks);
        uint self_risk_2 = risk.balanceOf(self);
        assertEq(rico.balanceOf(bank), 1);
        assertGt(self_risk_1, self_risk_2);
    }

    function test_keep_unbalanced_slightly_more_sin() public {
        Vat(bank).filk(gilk, 'fee', bytes32(2 * RAY));

        feedpush(grtag, bytes32(RAY * 1000), block.timestamp + 1000);
        uint amt = Vat(bank).sin() / RAY - 1;
        Vat(bank).frob(gilk, address(this), abi.encodePacked(amt), int(amt));
        skip(1);

        feedpush(grtag, bytes32(0), block.timestamp + 10000);

        assertEq(rico.balanceOf(bank), 0);
        Bank.Ramp memory ramp = Vow(bank).ramp();
        uint flop = min(wmul(ramp.rel, risk.totalSupply()), ramp.vel) * min(block.timestamp - ramp.bel, ramp.cel);
        feedpush(RISK_RICO_TAG, bytes32(RAY), block.timestamp + 1000);
        uint risk_ts1 = risk.totalSupply();
        Vow(bank).keep(ilks);
        uint risk_ts2 = risk.totalSupply();
        assertGt(rico.balanceOf(bank), 1);
        assertEq(Vat(bank).sin(), 2 * RAY);
        assertEq(risk_ts2, risk_ts1 + flop);
    }

    function test_bail_hook() public {
        FrobHook hook = new FrobHook();
        Vat(bank).filk(gilk, 'hook', bytes32(uint(bytes32(bytes20(address(hook))))));
        Vat(bank).frob(gilk, self, abi.encodePacked(WAD), int(WAD));
        uint vowgoldbefore = gold.balanceOf(bank);

        ZeroHook zhook = new ZeroHook();
        Vat(bank).filk(gilk, 'hook', bytes32(uint(bytes32(bytes20(address(zhook))))));
        vm.expectCall(address(zhook), abi.encodePacked(zhook.bailhook.selector));
        Vat(bank).bail(gilk, self);
        assertEq(gold.balanceOf(bank), vowgoldbefore);
    }
}

contract FrobHook is Hook {
    function frobhook(
        address , bytes32 , address , bytes calldata dink, int dart
    ) external pure returns (bool safer){
        return int(uint(bytes32(dink[:32]))) >= 0 && dart <= 0; 
    }
    function bailhook(
        bytes32 i, address u, uint bill, address keeper, uint rush, uint cut
    ) external returns (bytes memory) {}
    function safehook(
        bytes32 , address
    ) external pure returns (uint, uint){return(uint(10 ** 18 * 10 ** 27), type(uint256).max);}
    function ink(bytes32, address) pure external returns (bytes memory) {
        return abi.encode(uint(0));
    }
}
contract ZeroHook is Hook {
    function frobhook(
        address sender, bytes32 i, address u, bytes calldata dink, int dart
    ) external returns (bool safer) {}
    function bailhook(
        bytes32 i, address u, uint bill, address keeper, uint rush, uint cut
    ) external returns (bytes memory) {}
    function safehook(
        bytes32 , address
    ) external pure returns (uint, uint){return(uint(0), type(uint256).max);}
    function ink(bytes32, address) pure external returns (bytes memory) {
        return abi.encode(uint(0));
    }
}

contract Usr {
    WethLike weth;
    address payable bank;
    Vat vat;
    constructor(address payable _bank, WethLike _weth) {
        weth = _weth;
        bank = _bank;
    }
    function deposit() public payable {
        weth.deposit{value: msg.value}();
    }
    function approve(address usr, uint amt) public {
        weth.approve(usr, amt);
    }
    function frob(bytes32 ilk, address usr, bytes calldata dink, int dart) public {
        Vat(bank).frob(ilk, usr, dink, dart);
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
        bob = new Usr(bank, weth);
        cat = new Usr(bank, weth);
        b = address(bob);
        c = address(cat);
        i0 = wilk;
        ilks.push(i0);

        weth.deposit{value: 6000 * WAD}();
        risk.mint(me, 10000 * WAD);
        weth.approve(bank, UINT256_MAX);

        File(bank).file('ceil', bytes32(uint(10000 * RAD)));
        Vat(bank).filk(i0, 'line', bytes32(10000 * RAD));
        Vat(bank).filk(i0, 'chop', bytes32(RAY * 11 / 10));

        File(bank).file('vel', bytes32(uint(WAD)));
        File(bank).file('rel', bytes32(uint(WAD / 10000)));
        File(bank).file('bel', bytes32(uint(0)));
        File(bank).file('cel', bytes32(uint(60)));

        feedpush(wrtag, bytes32(RAY), block.timestamp + 2 * BANKYEAR);
        feedpush(grtag, bytes32(RAY), block.timestamp + 2 * BANKYEAR);
        uint fee = 1000000001546067052200000000; // == ray(1.05 ** (1/BANKYEAR))
        Vat(bank).filk(i0, 'fee', bytes32(fee));
        Vat(bank).frob(i0, me, abi.encodePacked(100 * WAD), 0);
        Vat(bank).frob(i0, me, abi.encodePacked(int(0)), int(99 * WAD));

        uint bal = rico.balanceOf(me);
        assertEq(bal, 99 * WAD);
        (Vat.Spot safe1,,) = Vat(bank).safe(i0, me);
        assertEq(uint(safe1), uint(Vat.Spot.Safe));

        cat.deposit{value: 7000 * WAD}();
        cat.approve(bank, UINT256_MAX);
        cat.frob(i0, c, abi.encodePacked(4001 * WAD), int(4000 * WAD));
        cat.transfer(arico, me, 4000 * WAD);

        weth.approve(address(router), UINT256_MAX);
        rico.approve(address(router), UINT256_MAX);
        risk.approve(address(router), UINT256_MAX);
        dai.approve(address(router), UINT256_MAX);
        weth.approve(bank, UINT256_MAX);
        rico.approve(bank, UINT256_MAX);
        risk.approve(bank, UINT256_MAX);
        dai.approve(bank, UINT256_MAX);

        PoolArgs memory dai_rico_args = getArgs(DAI, 2000 * WAD, arico, 2000 * WAD, 500, x96(1));
        join_pool(dai_rico_args);

        PoolArgs memory risk_rico_args = getArgs(arisk, 2000 * WAD, arico, 2000 * WAD, 3000, x96(1));
        join_pool(risk_rico_args);
        rico_risk_pool = getPoolAddr(arisk, arico, 3000);
        
        File(bank).file('vel', bytes32(uint(200 * WAD)));
        File(bank).file('rel', bytes32(uint(WAD)));
        File(bank).file('bel', bytes32(uint(block.timestamp)));
        File(bank).file('cel', bytes32(uint(1)));
        guy = new Guy(bank);
    }

    function test_bail_urns_1yr_unsafe() public {
        // wait a year, flap the surplus
        skip(BANKYEAR);
        uint start_ink = _ink(i0, me);
        feedpush(RICO_RISK_TAG, bytes32(RAY), UINT256_MAX);
        Vow(bank).keep(ilks);

        (Vat.Spot spot,,) = Vat(bank).safe(i0, me);
        assertEq(uint(spot), uint(Vat.Spot.Sunk));

        // should be balanced
        uint sin0 = Vat(bank).sin();
        uint vow_rico0 = rico.balanceOf(bank);
        assertEq(sin0 / RAY, 0);
        assertEq(vow_rico0, 0);

        // bail the urn frobbed in setup
        rico_mint(1000 * WAD, false);
        rico.transfer(address(guy), 1000 * WAD);
        guy.approve(arico, ahook, UINT256_MAX);
        vm.expectCall(address(hook), abi.encodePacked(ERC20Hook.bailhook.selector));
        Vat(bank).bail(i0, me);
        // urn should be bailed
        uint ink = _ink(i0, me); uint art = _art(i0, me);
        assertEq(art, 0);
        assertLt(ink, start_ink);

        uint sin1 = Vat(bank).sin();
        uint vow_rico1 = rico.balanceOf(bank);
        assertEq(art, 0);
        assertGt(sin1, 0);
        assertGt(vow_rico1, 0);
    }

    function test_bail_urns_when_safe() public {
        vm.expectRevert(Vat.ErrSafeBail.selector);
        Vat(bank).bail(i0, me);

        uint sin0 = Vat(bank).sin();
        assertEq(sin0 / RAY, 0);

        skip(BANKYEAR);
        feedpush(wrtag, bytes32(0), UINT256_MAX);

        vm.expectCall(address(hook), abi.encodePacked(hook.bailhook.selector));
        Vat(bank).bail(i0, me);
        vm.expectRevert(Vat.ErrSafeBail.selector);
        Vat(bank).bail(i0, me);
    }

    function test_keep_vow_1yr_drip_flap() public {
        uint initial_total = rico.totalSupply();
        skip(BANKYEAR);
        feedpush(RICO_RISK_TAG, bytes32(RAY), UINT256_MAX);
        //vm.expectCall(address(hook), abi.encodePacked(hook.flow.selector));
        Vow(bank).keep(ilks);
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
        feedpush(wrtag, bytes32(RAY / 2), UINT256_MAX);
        vm.expectCall(address(hook), abi.encodePacked(hook.bailhook.selector));
        Vat(bank).bail(i0, me);
        rico_mint(WAD * 5000, false);
        Vat(bank).bail(i0, address(cat));

        // more sin than rico, should flop
        feedpush(RISK_RICO_TAG, bytes32(RAY), UINT256_MAX);
        vm.expectCall(bank, abi.encodePacked(Vat.heal.selector));
        Vow(bank).keep(ilks);
    }

    function test_keep_rate_limiting_flop_absolute_rate() public {
        File(bank).file('ceil', bytes32(uint(100000 * RAD)));
        Vat(bank).filk(i0, 'line', bytes32(100000 * RAD));
        File(bank).file('vel', bytes32(uint(WAD)));
        File(bank).file('rel', bytes32(uint(WAD)));
        File(bank).file('bel', bytes32(uint(block.timestamp - 1)));
        File(bank).file('cel', bytes32(uint(1)));

        assertGt(risk.totalSupply(), WAD);
        prepguyrico(10000 * WAD, true);
        Vow(bank).keep(ilks);
    }

    function test_keep_rate_limiting_flop_relative_rate() public {
        File(bank).file('ceil', bytes32(uint(100000 * RAD)));
        Vat(bank).filk(i0, 'line', bytes32(uint(100000 * RAD)));
        File(bank).file('rel', bytes32(uint(WAD)));
        File(bank).file('vel', bytes32(uint(risk.totalSupply() * 2)));
        File(bank).file('bel', bytes32(uint(block.timestamp - 1)));
        File(bank).file('cel', bytes32(uint(1)));

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
        guy.approve(arisk, bank, UINT256_MAX);
        guy.keep(ilks);

        skip(60);
        feedpush(RICO_RISK_TAG, bytes32(10000 * RAY), UINT256_MAX);
        risk.mint(address(guy), 1000 * WAD);
        Vow(bank).keep(ilks); // call again to burn risk given to vow the first time

        uint risk_post_flap_supply = risk.totalSupply();
        assertLt(risk_post_flap_supply, risk_initial_supply + 1000 * WAD * 2);

        // confirm bail trades the weth for rico
        uint vow_rico_0 = rico.balanceOf(bank);
        uint hook_weth_0 = weth.balanceOf(bank);
        vm.expectCall(address(hook), abi.encodePacked(hook.bailhook.selector));
        Vat(bank).bail(i0, me);

        uint vow_pre_flop_rico = rico.balanceOf(bank);
        feedpush(RISK_RICO_TAG, bytes32(10 * RAY), UINT256_MAX);
        prepguyrico(2000 * WAD, false);
        //vm.expectCall(address(hook), abi.encodePacked(hook.flow.selector));
        guy.keep(ilks);

        // now vow should hold more rico
        uint vow_post_flop_rico = rico.balanceOf(bank);
        assertGt(vow_post_flop_rico, vow_pre_flop_rico);

        // now complete the liquidation
        feedpush(wrtag, bytes32(100 * RAY), UINT256_MAX);
        uint vow_rico_1 = rico.balanceOf(bank);
        uint vat_weth_1 = weth.balanceOf(bank);
        assertGt(vow_rico_1, vow_rico_0);
        assertLt(vat_weth_1, hook_weth_0);
    }
}

