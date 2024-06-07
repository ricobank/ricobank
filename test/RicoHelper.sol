// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.25;
import 'forge-std/Test.sol';

import '../src/mixin/math.sol';
import { Gem, GemFab } from '../lib/gemfab/src/gem.sol';
import { Bank } from '../src/bank.sol';
import { BaseHelper, BankDiamond } from './BaseHelper.sol';
import { Ball, File, Vat, Vow, Vox } from '../src/ball.sol';

contract Guy {
    address payable bank;

    constructor(address payable _bank) {
        bank = _bank;
    }
    function approve(address gem, address dst, uint amt) public {
        Gem(gem).approve(dst, amt);
    }
    function frob(bytes32 ilk, address usr, int dink, int dart) public {
        Vat(bank).frob(ilk, usr, dink, dart);
    }
    function transfer(address gem, address dst, uint amt) public {
        Gem(gem).transfer(dst, amt);
    }
    function bail(bytes32 i, address u) public returns (uint) {
        return Vat(bank).bail(i, u);
    }
    function keep(bytes32[] calldata ilks) public {
        Vow(bank).keep(ilks);
    }
}

abstract contract RicoSetUp is BaseHelper {
    bytes32 constant public rilk  = "risk";
    uint256 constant public INIT_PAR   = RAY;
    uint256 constant public init_mint  = 10000;
    uint256 constant public FEE_2X_ANN = uint(1000000021964508944519921664);
    uint256 constant public FEE_1_5X_ANN = uint(1000000012848414058163994624);

    Ball       public ball;
    Gem        public rico;
    Gem        public risk;
    GemFab     public gemfab;
    address    public arico;
    address    public arisk;

    Guy _bob;
    Guy guy;

    // mint some risk to a fake account to frob some rico
    function rico_mint(uint amt, bool bail) internal {
        uint start_risk = risk.balanceOf(self);

        // create fake account and mint some risk to it
        _bob = new Guy(bank);
        uint risk_amt = amt * 1000;
        risk_mint(address(_bob), risk_amt);
        _bob.approve(arisk, bank, risk_amt);

        // bob borrows the rico and sends back to self
        _bob.frob(rilk, address(_bob), int(risk_amt), int(amt));
        _bob.transfer(arico, self, amt);

        if (bail) {
            uint liqr = uint(Vat(bank).get(rilk, 'liqr'));
            Vat(bank).filk(rilk, 'liqr', bytes32(UINT256_MAX));
            Vat(bank).bail(rilk, address(_bob));
            Vat(bank).filk(rilk, 'liqr', bytes32(liqr));
        }

        // restore previous risk supply
        risk_burn(self, risk.balanceOf(self) - start_risk);
    }

    // use to modify risk and wal together
    function risk_mint(address usr, uint wad) internal {
        risk.mint(usr, wad);
        uint orig_wal = Vow(bank).wal();
        file('wal', bytes32(orig_wal + wad));
    }
    function risk_burn(address usr, uint wad) internal {
        risk.burn(usr, wad);
        uint orig_wal = Vow(bank).wal();
        file('wal', bytes32(orig_wal - wad));
    }

    function force_fees(uint gain) public {
        // Create imaginary fees, add to joy
        // Avoid manipulating vat like this usually
        uint256 joy_0    = Vat(bank).joy();
        uint256 joy_idx  = 2;
        bytes32 vat_info = 'vat.0';
        bytes32 vat_pos  = keccak256(abi.encodePacked(vat_info));
        bytes32 joy_pos  = bytes32(uint(vat_pos) + joy_idx);

        vm.store(bank, joy_pos,  bytes32(joy_0  + gain));
    }

    function force_sin(uint val) public {
        // set sin as if it was covered by a good bail
        uint256 sin_idx  = 3;
        bytes32 vat_info = 'vat.0';
        bytes32 vat_pos  = keccak256(abi.encodePacked(vat_info));
        bytes32 sin_pos  = bytes32(uint(vat_pos) + sin_idx);

        vm.store(bank, sin_pos, bytes32(val));
    }

    function make_bank() public {
        gemfab = new GemFab();
        rico   = gemfab.build(bytes32("Rico"), bytes32("RICO"));
        risk   = gemfab.build(bytes32("Rico Riskshare"), bytes32("RISK"));
        arico  = address(rico);
        arisk  = address(risk);

        bank       = make_diamond();

        // deploy bank with one ERC20 ilk and one NFPM ilk
        Ball.IlkParams[] memory ips = new Ball.IlkParams[](1);
        ips[0] = Ball.IlkParams(
            'first',
            RAY, // chop
            RAY / 10, // dust
            1000000001546067052200000000, // fee
            100000 * RAD, // line
            RAY // liqr
        );

        Ball.BallArgs memory bargs = Ball.BallArgs(
            bank,
            arico,
            arisk,
            INIT_PAR,
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

        ball.setup(bargs);
        ball.makeilk(ips[0]);
        ball.approve(self);
        BankDiamond(bank).acceptOwnership();

        ////////// these are outside ball, but must be part of real deploy process, unless warding ball first w create2
        Gem(rico).ward(bank, true);
        Gem(risk).ward(bank, true);
        //////////
    }

    function init_risk_ilk(bytes32 ilk) public {
        risk.approve(bank, type(uint256).max);
        Vat(bank).init(ilk);
        Vat(bank).filk(ilk, 'liqr', bytes32(RAY));
        Vat(bank).filk(ilk, 'pep',  bytes32(uint(2)));
        Vat(bank).filk(ilk, 'pop',  bytes32(RAY));
        Vat(bank).filk(ilk, 'chop', bytes32(RAY));
        Vat(bank).filk(ilk, 'line', bytes32(init_mint * 10 * RAD));
        Vat(bank).filk(ilk, 'fee',  bytes32(uint(1000000001546067052200000000)));  // 5%
    }

    function init_risk() public {
        risk_mint(self, init_mint * WAD);
        init_risk_ilk(rilk);
    }

    // mint some new rico and give it to guy
    function prepguyrico(uint amt, bool bail) internal {
        rico_mint(amt, bail);
        rico.transfer(address(guy), amt);
    }

    function check_integrity() internal view {
        uint sup  = rico.totalSupply();
        uint joy  = Vat(bank).joy();
        uint sin  = Vat(bank).sin();
        uint rest = Vat(bank).rest();
        uint tart = Vat(bank).ilks(rilk).tart;
        uint rack = Vat(bank).ilks(rilk).rack;

        assertEq(rico.balanceOf(bank), 0);
        assertEq(tart * rack + sin, (sup + joy) * RAY + rest);
    }

    modifier _check_integrity_after_ {
        _;
        check_integrity();
    }

}
