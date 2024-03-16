// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { Flasher } from "./Flasher.sol";
import {
    RicoSetUp, Guy, BankDiamond, Bank, File, Vat, Vow, Hook, Gem, Ball
} from "./RicoHelper.sol";
import '../src/mixin/math.sol';

contract IntegrationTest is Test, RicoSetUp {

    function setUp() public {
        make_bank();
        init_gold();
        risk.mint(self, 10_000 * WAD);
    }
    
    function test_joy_accounting() public {
        // accumulate some fees
        Vat(bank).frob(gilk, self, abi.encodePacked(10 * WAD), int(5 * WAD));
        skip(100);
        Vat(bank).drip(gilk);
        check_integrity();

        // system is in surplus, flap
        set_dxm('dam', RAY);
        Vow(bank).keep(single(gilk));
        check_integrity();

        // borrow some rico to fill the bail, then bail
        rico_mint(6 * WAD, false);
        feedpush(grtag, bytes32(RAY / 4), type(uint).max);
        Vat(bank).bail(gilk, self);
        check_integrity();

        // system is in deficit, flop
        set_dxm('dom', RAY);
        Vow(bank).keep(single(gilk));
        check_integrity();
    }

    function test_bail_joy_direction() public _check_integrity_after_ {
        // open an urn to bail
        Vat(bank).frob(gilk, self, abi.encodePacked(10 * WAD), int(5 * WAD));

        // mint some rico to fill the bail
        rico_mint(6 * WAD, false);

        feedpush(grtag, bytes32(RAY / 4), type(uint).max);
        uint sup0 = rico.totalSupply();
        uint joy0 = Vat(bank).joy();

        // bail should raise joy, because bailer is paying rico for the ink
        Vat(bank).bail(gilk, self);

        uint sup1 = rico.totalSupply();
        uint joy1 = Vat(bank).joy();
        assertGt(joy1, joy0);
        assertLt(sup1, sup0);
    }

    function test_flap_joy_direction() public _check_integrity_after_ {
        // open an urn to accumulate fees, mint some risk to fill the flop
        Vat(bank).frob(gilk, self, abi.encodePacked(10 * WAD), int(5 * WAD));
        skip(100);
        Vat(bank).drip(gilk);
        risk.mint(self, 10_000 * WAD);

        uint rico_sup0 = rico.totalSupply();
        uint risk_sup0 = risk.totalSupply();
        uint joy0 = Vat(bank).joy();

        // joy should decrease, because it's being flapped
        set_dxm('dam', RAY);
        Vow(bank).keep(single(gilk));

        uint rico_sup1 = rico.totalSupply();
        uint risk_sup1 = risk.totalSupply();
        uint joy1 = Vat(bank).joy();
        assertLt(joy1, joy0);
        assertLt(risk_sup1, risk_sup0);
        assertGt(rico_sup1, rico_sup0);
    }

    function test_flop_joy_direction() public _check_integrity_after_ {
        risk.mint(self, 10_000 * WAD);
        skip(100);

        // open an urn and bail it when ink is worthless
        // urn's whole tab becomes sin
        rico_mint(10 * WAD, true);

        uint rico_sup0 = rico.totalSupply();
        uint risk_sup0 = risk.totalSupply();
        uint joy0 = Vat(bank).joy();

        // joy should increase, because keeper is paying rico for risk
        set_dxm('dom', RAY);
        Vow(bank).keep(single(gilk));

        uint rico_sup1 = rico.totalSupply();
        uint risk_sup1 = risk.totalSupply();
        uint joy1 = Vat(bank).joy();
        assertGt(joy1, joy0);
        assertGt(risk_sup1, risk_sup0);
        assertLt(rico_sup1, rico_sup0);
    }
}
