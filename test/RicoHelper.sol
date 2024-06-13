// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.25;
import 'forge-std/Test.sol';

import '../src/mixin/math.sol';
import { Gem, GemFab } from '../lib/gemfab/src/gem.sol';
import { Bank } from '../src/bank.sol';
import { BaseHelper } from './BaseHelper.sol';

contract Guy {
    Bank bank;

    constructor(Bank _bank) {
        bank = _bank;
    }
    function approve(address gem, address dst, uint amt) public {
        Gem(gem).approve(dst, amt);
    }
    function frob(address usr, int dink, int dart) public {
        bank.frob(usr, dink, dart);
    }
    function transfer(address gem, address dst, uint amt) public {
        Gem(gem).transfer(dst, amt);
    }
    function bail(address u) public returns (uint) {
        return bank.bail(u);
    }
    function keep() public {
        bank.keep();
    }
}

abstract contract RicoSetUp is BaseHelper {
    uint256 constant public init_mint  = 10000;
    uint256 constant public FEE_2X_ANN = uint(1000000021964508944519921664);
    uint256 constant public FEE_1_5X_ANN = uint(1000000012848414058163994624);

    GemFab     public gemfab;

    Guy _bob;
    Guy guy;

    // mint some risk to a fake account to frob some rico
    function rico_mint(uint amt, bool bail) internal {
        uint start_risk = risk.balanceOf(self);

        // create fake account and mint some risk to it
        _bob = new Guy(bank);
        uint risk_amt = amt * 1000;
        risk_mint(address(_bob), risk_amt);

        // bob borrows the rico and sends back to self
        _bob.frob(address(_bob), int(risk_amt), int(amt));
        _bob.transfer(arico, self, amt);

        if (bail) {
            uint liqr = bank.liqr();
            file('liqr', bytes32(UINT256_MAX));
            bank.bail(address(_bob));
            file('liqr', bytes32(liqr));
        }

        // restore previous risk supply
        risk_burn(self, risk.balanceOf(self) - start_risk);
    }

    // use to modify risk and wal together
    function risk_mint(address usr, uint wad) internal {
        risk.mint(usr, wad);
        uint orig_wal = bank.wal();
        file('wal', bytes32(orig_wal + wad));
    }
    function risk_burn(address usr, uint wad) internal {
        risk.burn(usr, wad);
        uint orig_wal = bank.wal();
        file('wal', bytes32(orig_wal - wad));
    }

    function force_fees(uint gain) public {
        // Create imaginary fees, add to joy
        // Avoid manipulating vat like this usually
        uint256 joy_0    = bank.joy();
        bytes32 joy_pos  = bytes32(uint(1));

        vm.store(abank, joy_pos,  bytes32(joy_0  + gain));
    }

    function force_sin(uint val) public {
        // set sin as if it was covered by a good bail
        bytes32 sin_pos  = bytes32(uint(2));
        vm.store(abank, sin_pos, bytes32(val));
    }

    function make_bank() public {
        gemfab = new GemFab();
        rico   = gemfab.build(bytes32("Rico"), bytes32("RICO"));
        risk   = gemfab.build(bytes32("Rico Riskshare"), bytes32("RISK"));
        arico  = address(rico);
        arisk  = address(risk);

        Bank.BankParams memory p = basic_params;
        p.rico = arico;
        p.risk = arisk;
        risk.mint(self, init_mint * WAD);
        bang(p);

        ////////// these are outside ball, but must be part of real deploy process, unless warding ball first w create2
        rico.ward(abank, true);
        risk.ward(abank, true);
        //////////
    }

    // mint some new rico and give it to guy
    function prepguyrico(uint amt, bool bail) internal {
        rico_mint(amt, bail);
        rico.transfer(address(guy), amt);
    }

    function check_integrity() internal view {
        uint sup  = rico.totalSupply();
        uint joy  = bank.joy();
        uint sin  = bank.sin();
        uint rest = bank.rest();
        uint tart = bank.tart();
        uint rack = bank.rack();

        assertEq(rico.balanceOf(abank), 0);
        assertEq(tart * rack + sin, (sup + joy) * RAY + rest);
    }

    modifier _check_integrity_after_ {
        _;
        check_integrity();
    }

}
