pragma solidity ^0.8.25;

import { BaseHelper, Gem, GemFab, Bank } from './RicoHelper.sol';
import 'forge-std/Test.sol';

contract BallTest is BaseHelper {
    uint256 constant init_par = RAY * 4;
    uint256 riskamt;

    GemFab  gf;

    int256  safedart;

    uint initial_risk_supply = 1000000 * WAD;
    uint start_time;

    function setUp() public {
        start_time = block.timestamp;
        gf         = new GemFab();

        // rico and risk created separately from ball
        // ball never wards them
        rico = gf.build(bytes32("Rico"), bytes32("RICO"));
        risk = gf.build(bytes32("Rico Riskshare"), bytes32("RISK"));
        arico = payable(address(rico));
        arisk = payable(address(risk));
        basic_params.rico = arico;
        basic_params.risk = arisk;

        Bank.BankParams memory p = Bank.BankParams(
            arico,
            arisk,
            init_par,
            RAY, // wel
            RAY * 9999999 / 10000000, // dam
            RAY * WAD, // pex
            WAD, // gif (82400 RISK/yr)
            999999978035500000000000000, // mop (~-50%/yr)
            937000000000000000, // lax (~3%/yr)
            1000000000000003652500000000, // how
            1000000021970000000000000000, // cap
            RAY, // way
            RAY, // chop
            init_dust, // dust
            1000000001546067052200000000, // fee
            100000 * RAD, // line
            RAY, // liqr
            2, // pep
            RAY, // pop
            0 // pup
        );

        risk.mint(self, initial_risk_supply);
        bank = new Bank(p);
        abank = payable(address(bank));

        // give bank mint/burn power
        rico.ward(abank, true);
        risk.ward(abank, true);

        // need to wait some time for uni adapters to work
        skip(BANKYEAR / 2);

        riskamt = risk.totalSupply() / 100;
        // find a rico borrow amount which will be safe by about 10%
        // risk * riskref = art * par
        safedart = int(rdiv(riskamt, init_par) * 10 / 11);
    }

    // apply to tests that create a surplus
    modifier _flap_after_ {
        _;
        risk.mint(self, 10000 * WAD);
        bank.frob(self, 0, 0); // just drip

        uint pre_bank_risk = risk.balanceOf(abank);
        uint pre_bank_rico = rico.balanceOf(abank);
        uint pre_bank_joy  = bank.joy();
        uint pre_user_risk = risk.balanceOf(self);
        uint pre_user_rico = rico.balanceOf(self);
        uint pre_risk_sup  = risk.totalSupply();

        vm.expectCall(arico, abi.encodePacked(Gem.mint.selector));
        vm.expectCall(arisk, abi.encodePacked(Gem.burn.selector));
        bank.keep();

        uint aft_bank_risk = risk.balanceOf(abank);
        uint aft_bank_rico = rico.balanceOf(abank);
        uint aft_bank_joy  = bank.joy();
        uint aft_user_risk = risk.balanceOf(self);
        uint aft_user_rico = rico.balanceOf(self);
        uint aft_risk_sup  = risk.totalSupply();

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

    modifier _balanced_after_ {
        _;
        // should not be any auctions
        uint me_risk_1 = risk.balanceOf(self);
        uint me_rico_1 = rico.balanceOf(self);

        bank.keep();

        uint me_risk_2 = risk.balanceOf(self);
        uint me_rico_2 = rico.balanceOf(self);

        assertEq(me_risk_1, me_risk_2);
        assertEq(me_rico_1, me_rico_2);
    }

    function test_ball_1() public {
        // simple bail
        bank.frob(self, int(riskamt), safedart);
        vm.expectRevert(Bank.ErrNotSafe.selector);
        bank.frob(self, int(0), safedart);
    }

    // frob, then flap (with wel == 100%), and check balanced
    function test_ball_pay_flap_success() public  _balanced_after_ {
        bank.frob(self, int(riskamt), safedart);

        skip(BANKYEAR * 100);

        uint ink_pre = _ink(self);
        uint art_pre = _art(self);

        assertEq(bank.wel(), RAY);

        vm.expectCall(arico, abi.encodePacked(Gem.mint.selector));
        bank.keep(); // drips

        uint rack = bank.rack();
        uint dust = bank.dust();
        int  dart = -int((art_pre * rack - dust) / rack);

        bank.frob(self, int(0), dart);

        uint ink_aft = _ink(self);
        assertEq(ink_aft, ink_pre);
        assertGt(ink_aft, rmul(dust, risk.totalSupply()));

        // balanced now because already kept
    }

    function test_bounds_fee() public {
        Bank.BankParams memory p = basic_params;
        // shouldn't be able to go under min
        p.fee = RAY - 1;
        vm.expectRevert(Bank.ErrBound.selector);
        new Bank(p);

        // test minimum
        p.fee = RAY;
        new Bank(p);

        // test max
        uint fee_max = bank.FEE_MAX();
        p.fee = fee_max;
        new Bank(p);

        // shouldn't be able to go over max
        p.fee = fee_max + 1;
        vm.expectRevert(Bank.ErrBound.selector);
        new Bank(p);
    }

    function test_bounds_2() public {
        Bank.BankParams memory p = basic_params;

        p.way = RAY;
        new Bank(p);

        p.wel = 0;
        new Bank(p);
        p.wel = RAY;
        new Bank(p);
        p.wel = RAY + 1;
        vm.expectRevert(Bank.ErrBound.selector);
        new Bank(p);
        p.wel = RAY;

        p.how = RAY;
        new Bank(p);
        p.how = UINT256_MAX;
        new Bank(p);
        p.how = RAY - 1;
        vm.expectRevert(Bank.ErrBound.selector);
        new Bank(p);
        p.how = RAY;

        p.cap = RAY;
        new Bank(p);
        uint cap_max = bank.CAP_MAX();
        p.cap = cap_max;
        new Bank(p);
        p.cap = cap_max + 1;
        vm.expectRevert(Bank.ErrBound.selector);
        new Bank(p);
        p.cap = RAY - 1;
        vm.expectRevert(Bank.ErrBound.selector);
        new Bank(p);
        p.cap = cap_max;

        p.how = RAY * 3 / 2;
        new Bank(p);
        p.way = RAY;
        new Bank(p);

        p.way = cap_max;
        new Bank(p);
        p.how = uint(1000000000000003652500000000);
        new Bank(p);
        p.way = cap_max + 1;
        vm.expectRevert(Bank.ErrBound.selector);
        new Bank(p);
        p.way = RAY;

        p.dam = 0;
        new Bank(p);
        p.dam = RAY;
        new Bank(p);
        p.dam = RAY + 1;
        vm.expectRevert(Bank.ErrBound.selector);
        new Bank(p);
    }

    function test_bounds_mine() public {
        Bank.BankParams memory p = basic_params;

        p.gif = UINT256_MAX;
        new Bank(p);
        p.gif = 0;
        new Bank(p);

        uint laxmax = bank.LAX_MAX();
        p.lax = laxmax;
        new Bank(p);
        p.lax = 0;
        new Bank(p);
        p.lax = laxmax + 1;
        vm.expectRevert(Bank.ErrBound.selector);
        new Bank(p);
    }

}
