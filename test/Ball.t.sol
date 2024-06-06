pragma solidity ^0.8.25;

import {
    File, Bank, Vat, Vow, Vox, BaseHelper, BankDiamond,
    Gem, GemFab, Ball
} from './RicoHelper.sol';
import { Diamond } from '../src/diamond.sol';
import 'forge-std/Test.sol';

contract BallTest is BaseHelper {
    uint256 constant init_par = RAY * 4;
    uint256 riskamt;

    bytes32 constant rilk  = 'risk';

    GemFab           gf;

    address rico;
    address risk;
    int256  safedart;

    bytes32[] ilks;

    uint initial_risk_supply = 1000000 * WAD;
    uint init_dust           = RAY / 100;
    uint start_time;
    Ball ball;

    function setUp() public {
        start_time = block.timestamp;
        gf         = new GemFab();

        // rico and risk created separately from ball
        // ball never wards them
        rico = address(gf.build(bytes32("Rico"), bytes32("RICO")));
        risk = address(gf.build(bytes32("Rico Riskshare"), bytes32("RISK")));

        // bank with two ilks
        bank    = make_diamond();
        ilks    = single(rilk);

        Ball.BallArgs memory bargs = Ball.BallArgs(
            bank,
            rico,
            risk,
            init_par,
            RAY, // wel
            RAY, // dam
            RAY * WAD, // pex
            WAD, // gif (82400 RISK/yr)
            999999978035500000000000000, // mop (~-50%/yr)
            937000000000000000, // lax (~3%/yr)
            1000000000000003652500000000, // how
            1000000021970000000000000000 // cap
        );

        ball = new Ball(bargs);

        BankDiamond(bank).transferOwnership(address(ball));

        // setup bank and ilks
        ball.setup(bargs);

        Ball.IlkParams memory ips = Ball.IlkParams(
            'risk',
            RAY, // chop
            init_dust, // dust
            1000000001546067052200000000, // fee
            100000 * RAD, // line
            RAY // liqr
        );
        ball.makeilk(ips);

        // transfer root access to self
        ball.approve(self);
        BankDiamond(bank).acceptOwnership();

        // give bank mint/burn power
        Gem(rico).ward(bank, true);
        Gem(risk).ward(bank, true);

        // need to wait some time for uni adapters to work
        skip(BANKYEAR / 2);

        Gem(risk).approve(bank, type(uint).max);
        Gem(risk).mint(address(this), initial_risk_supply);

        Gem(risk).mint(self, initial_risk_supply);
        riskamt = Gem(risk).totalSupply() / 100;
        // find a rico borrow amount which will be safe by about 10%
        // risk * riskref = art * par
        safedart = int(rdiv(riskamt, init_par) * 10 / 11);
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

    function test_ball_1() public {
        // simple bail
        Vat(bank).frob(rilk, self, int(riskamt), safedart);
        vm.expectRevert(Vat.ErrNotSafe.selector);
        Vat(bank).frob(rilk, self, int(0), safedart);
    }

    // frob, then flap (with wel == 100%), and check balanced
    function test_ball_pay_flap_success() public  _balanced_after_ {
        Vat(bank).frob(rilk, self, int(riskamt), safedart);

        skip(BANKYEAR * 100);

        uint ink_pre = _ink(rilk, self);
        uint art_pre = _art(rilk, self);

        assertEq(Vow(bank).wel(), RAY);

        set_dxm('dam', RAY);
        vm.expectCall(rico, abi.encodePacked(Gem.mint.selector));
        Vow(bank).keep(ilks); // drips

        uint rack = Vat(bank).ilks(rilk).rack;
        uint dust = Vat(bank).ilks(rilk).dust;
        int  dart = -int((art_pre * rack - dust) / rack);

        Vat(bank).frob(rilk, self, int(0), dart);

        uint ink_aft = _ink(rilk, self);
        assertEq(ink_aft, ink_pre);
        assertGt(ink_aft, rmul(dust, Gem(risk).totalSupply()));

        // balanced now because already kept
    }

    function test_ward() public {
        assertEq(BankDiamond(bank).owner(), address(this));

        vm.prank(address(gf));
        vm.expectRevert("Ownable: sender must be owner");
        File(bank).file('par', bytes32(RAY));

        BankDiamond(bank).transferOwnership(address(gf));
        assertEq(BankDiamond(bank).owner(), address(this));

        vm.prank(address(gf));
        vm.expectRevert("Ownable: sender must be owner");
        File(bank).file('par', bytes32(RAY));

        File(bank).file('par', bytes32(RAY));

        vm.prank(address(gf));
        BankDiamond(bank).acceptOwnership();
        assertEq(BankDiamond(bank).owner(), address(gf));

        vm.expectRevert("Ownable: sender must be owner");
        File(bank).file('par', bytes32(RAY));

        vm.prank(address(gf));
        File(bank).file('par', bytes32(RAY));
    }

    function test_bounds_fee() public {
        bytes32 rilk2 = 'risk2';
        Vat(bank).init(rilk2);

        // shouldn't be able to go under min
        vm.expectRevert(Bank.ErrBound.selector);
        Vat(bank).filk(rilk2, 'fee', bytes32(RAY - 1));

        // test minimum...rack should stick
        Vat(bank).filk(rilk2, 'fee', bytes32(RAY));

        skip(BANKYEAR);
        Vat(bank).drip(rilk2);
        assertEq(Vat(bank).ilks(rilk2).rack, RAY);

        // test max...rack should grow 10x/yr
        uint fee_max = Vat(bank).FEE_MAX();
        Vat(bank).filk(rilk2, 'fee', bytes32(fee_max));

        skip(BANKYEAR * 2);
        Vat(bank).drip(rilk2);
        assertClose(Vat(bank).ilks(rilk2).rack, 100 * RAY, 1000000000000);

        // shouldn't be able to go over max
        vm.expectRevert(Bank.ErrBound.selector);
        Vat(bank).filk(rilk2, 'fee', bytes32(fee_max + 1));
    }

    function test_bounds_2() public {
        uint wel = Vow(bank).wel();
        uint dam = Vow(bank).dam();
        uint pex = Vow(bank).pex();
        uint mop = Vow(bank).mop();
        uint lax = Vow(bank).lax();

        file('way', bytes32(RAY));
        file('wel', bytes32(0));
        file('wel', bytes32(RAY));
        vm.expectRevert(Bank.ErrBound.selector);
        new Vow(Bank.BankParams(rico, risk), Vow.VowParams(RAY + 1, dam, pex, mop, lax));

        file('how', bytes32(RAY));
        file('how', bytes32(UINT256_MAX));
        vm.expectRevert(Bank.ErrBound.selector);
        new Vox(Bank.BankParams(rico, risk), Vox.VoxParams(RAY - 1, RAY + 1));

        file('how', bytes32(RAY));
        uint cap_max = Vox(bank).CAP_MAX();
        file('cap', bytes32(RAY));
        file('cap', bytes32(cap_max));
        vm.expectRevert(Bank.ErrBound.selector);
        new Vox(Bank.BankParams(rico, risk), Vox.VoxParams(RAY + 1, cap_max + 1));

        file('how', bytes32(RAY * 3 / 2));
        file('way', bytes32(RAY));

        file('way', bytes32(cap_max));
        file('how', bytes32(uint(1000000000000003652500000000)));
        vm.expectRevert(Bank.ErrBound.selector);
        file('way', bytes32(cap_max+1));

        file('dam', 0);
        file('dam', bytes32(RAY));

        vm.expectRevert(Bank.ErrBound.selector);
        new Vow(Bank.BankParams(rico, risk), Vow.VowParams(wel, RAY + 1, pex, mop, lax));
    }

    function test_close() public {
        Diamond(bank).transferOwnership(address(ball));

        bytes32 hilk = 'hello';
        Vat(bank).init(hilk);
        Vat(bank).filk(hilk, 'line', bytes32(RAD));
        File(bank).file('par', bytes32(RAY));

        /* lock sequence */
        Diamond(bank).transferOwnership(address(ball));
        ball.accept();
        ball.transferOwnership(address(0));
        /* end of lock sequence. bank owned by ball, ball owned by 0x0 */

        vm.expectRevert('Ownable: sender must be owner');
        File(bank).file('par', bytes32(RAY));

        vm.expectRevert('Ownable: sender must be owner');
        ball.approve(self);

        assertEq(Diamond(bank).owner(), address(ball));
        assertEq(ball.owner(), address(0));
    }

    function test_bounds_mine() public {
        uint wel = Vow(bank).wel();
        uint dam = Vow(bank).dam();
        uint pex = Vow(bank).pex();
        uint mop = Vow(bank).mop();

        file('gif', bytes32(UINT256_MAX));
        file('gif', 0);

        file('phi', 0);
        file('phi', bytes32(block.timestamp));
        vm.expectRevert(Bank.ErrBound.selector);
        File(bank).file('phi', bytes32(block.timestamp + 1));

        uint laxmax = Vow(bank).LAX_MAX();
        file('lax', bytes32(laxmax));
        file('lax', 0);
        vm.expectRevert(Bank.ErrBound.selector);
        new Vow(Bank.BankParams(rico, risk), Vow.VowParams(
            wel, dam, pex, mop, laxmax + 1
        ));
    }

}
