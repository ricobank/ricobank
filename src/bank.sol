// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2021-2024 halys

pragma solidity ^0.8.25;

import { Math } from "./mixin/math.sol";
import { Flog } from "./mixin/flog.sol";
import { Palm } from "./mixin/palm.sol";
import { Gem }  from "../lib/gemfab/src/gem.sol";

contract Bank is Math, Flog, Palm {

    struct Urn {
        uint256 ink;   // [wad] Locked Collateral
        uint256 art;   // [wad] Normalised Debt
    }

    struct BankParams {
        address rico;
        address risk;
        uint256 par;
        uint256 wel;
        uint256 dam;
        uint256 pex;
        uint256 gif;
        uint256 mop;
        uint256 lax;
        uint256 how;
        uint256 cap;
        uint256 way;

        uint256 chop;
        uint256 dust;
        uint256 fee;
        uint256 line;
        uint256 liqr;
        uint256 pep;
        uint256 pop;
        int256  pup;
   }

    Gem immutable public rico;
    Gem immutable public risk;

    // vat
    mapping (address => Urn ) public urns; // CDPs
    uint256 public joy;   // [wad]
    uint256 public sin;   // [rad]
    uint256 public rest;  // [rad] Debt remainder
    uint256 public par;   // [ray] System Price (rico/ref)
    uint256 public tart;  // [wad] Total Normalised Debt
    uint256 public rack;  // [ray] Accumulated Rate
    uint256 public line;  // [rad] Debt Ceiling
    uint256 public rho;   // [sec] Time of last drip
    uint256 immutable public fee;   // [ray] per-second compounding rate
    uint256 immutable public dust;  // [ray] Urn Ink Floor, as a fraction of totalSupply
    uint256 immutable public chop;  // [ray] Liquidation Penalty
    uint256 immutable public liqr;  // [ray] Liquidation Ratio
    uint256 immutable public pep;   // [ray] discount exponent
    uint256 immutable public pop;   // [ray] discount offset
    int256  immutable public pup;   // [ray] signed discount shift
    uint256 constant  public FEE_MAX = 1000000072964521287979890107; // ~10x/yr

    // vow
    uint256 public bel;  // [sec] last flap timestamp
    uint256 public gif;  // initial RISK base mint rate
    uint256 public phi;  // [sec] last mine timestamp
    uint256 public wal;  // risk deposited + risk totalSupply
    uint256 immutable public pex; // [ray] start price
    uint256 immutable public wel; // [ray] fraction of joy/flap
    uint256 immutable public dam; // [ray] per-second flap discount
    uint256 immutable public mop; // [ray] per-second gif decay
    uint256 immutable public lax; // [ray] mint-rate shift up (fraction of totalSupply)
    uint256 constant  public LAX_MAX = 145929047899781146998; // ~100x/yr
    uint256 constant         SAFE = RAY;

    // vox
    uint256 public way; // [ray] System Rate (SP growth rate)
    uint256 immutable public how;
    uint256 immutable public cap;
    uint256 constant  public CAP_MAX = 1000000072964521287979890107; // ~10x/yr

    error ErrDebtCeil();
    error ErrNotSafe();
    error ErrSafeBail();
    error ErrUrnDust();
    error ErrWrongUrn();
    error ErrBound();

    function must(uint actual, uint lo, uint hi) internal pure {
        if (actual < lo || actual > hi) revert ErrBound();
    }

    constructor(BankParams memory p) {
        (rico, risk) = (Gem(p.rico), Gem(p.risk));

        (wel, dam, pex, mop, lax) = (p.wel, p.dam, p.pex, p.mop, p.lax);
        must(wel, 0, RAY);
        must(dam, 0, RAY);
        must(pex, RAY, RAY * WAD);
        must(mop, 0, RAY);
        must(lax, 0, LAX_MAX);

        (how, cap) = (p.how, p.cap);
        must(how, RAY, type(uint).max);
        must(cap, RAY, CAP_MAX);

        (par, line, dust) = (p.par, p.line, p.dust);
        must(dust, 0, RAY);

        (pep, pop, pup) = (p.pep, p.pop, p.pup);

        (liqr, chop, fee) = (p.liqr, p.chop, p.fee);
        must(liqr, RAY, type(uint).max);
        must(chop, RAY, 10 * RAY);
        must(fee, RAY, FEE_MAX);

        (rack, rho, bel) = (RAY, block.timestamp, block.timestamp);

        (gif, phi, wal) = (p.gif, block.timestamp, risk.totalSupply());
        must(wal, 0, RAD);

        way = p.way;
        must(way, rinv(cap), cap);

        emit NewPalm0("par", bytes32(par));
        emit NewPalm0("line", bytes32(line));
        emit NewPalm0("rho",  bytes32(rho));
        emit NewPalm0("bel", bytes32(bel));
        emit NewPalm0("gif", bytes32(gif));
        emit NewPalm0("phi", bytes32(phi));
        emit NewPalm0("wal", bytes32(wal));
        emit NewPalm0("way", bytes32(way));
    }

    function safe(address u)
      public view returns (uint deal, uint tot)
    {
        Urn storage urn = urns[u];
        uint ink = urn.ink;

        // par acts as a multiplier for collateral requirements
        // par increase has same effect on cut as fee accumulation through rack
        // par decrease acts like a negative fee
        uint tab = urn.art * rmul(par, rack);
        uint cut = rdiv(ink, liqr) * RAY;

        // min() used to prevent truncation hiding unsafe
        deal = tab > cut ? min(cut / (tab / RAY), SAFE - 1) : SAFE;
        tot  = ink * RAY;
    }

    // modify CDP
    function frob(address u, int dink, int dart)
      external payable _flog_
    {
        Urn storage urn = urns[u];

        uint _rack = _drip();

        // modify normalized debt
        uint256 art = add(urn.art, dart);
        urn.art     = art;
        emit NewPalm1("art", bytes32(bytes20(u)), bytes32(art));

        // keep track of total so it denorm doesn't exceed line
        tart    = add(tart, dart);
        emit NewPalm0("tart", bytes32(tart));

        uint _rest;
        // rico mint/burn amount increases with rack
        int dtab = mul(_rack, dart);
        if (dtab > 0) {
            // borrow
            // dtab is a rad
            uint wad = uint(dtab) / RAY;

            // remainder is a ray
            _rest = rest += uint(dtab) % RAY;
            emit NewPalm0("rest", bytes32(_rest));

            rico.mint(msg.sender, wad);
        } else if (dtab < 0) {
            // paydown
            // dtab is a rad, so burn one extra to round in system's favor
            uint wad = (uint(-dtab) / RAY) + 1;
            // accrue excess from rounding to rest
            _rest = rest += add(wad * RAY, dtab);
            emit NewPalm0("rest", bytes32(_rest));

            rico.burn(msg.sender, wad);
        }

        // update balance before transferring tokens
        uint ink = add(urn.ink, dink);
        urn.ink = ink;
        emit NewPalm1("ink", bytes32(bytes20(u)), bytes32(ink));

        if (dink > 0) {
            // pull tokens from sender
            risk.burn(msg.sender, uint(dink));
        } else if (dink < 0) {
            // return tokens to urn holder
            risk.mint(u, uint(-dink));
        }

        // urn is safer, or it is safe
        if (dink < 0 || dart > 0) {
            (uint deal,) = safe(u);
            if (u != msg.sender) revert ErrWrongUrn();
            if (deal < SAFE) revert ErrNotSafe();
        }

        // urn has no debt, or a non-dusty ink amount
        if (art != 0 && urn.ink < rmul(wal, dust)) revert ErrUrnDust();

        // either debt has decreased, or debt ceiling is not exceeded
        if (dart > 0) if (tart * _rack > line) revert ErrDebtCeil();
    }

    // liquidate CDP
    function bail(address u)
      external payable _flog_ returns (uint sell)
    {
        uint _rack = _drip();
        (uint deal, uint tot) = safe(u);
        if (deal == SAFE) revert ErrSafeBail();
        Urn storage urn = urns[u];

        uint art = urn.art;
        urn.art  = 0;
        emit NewPalm1("art", bytes32(bytes20(u)), bytes32(uint(0)));

        uint dtab = art * _rack;
        tart     -= art;

        emit NewPalm0("tart", bytes32(tart));

        // record the bad debt for vow to heal
        sin += dtab;
        emit NewPalm0("sin", bytes32(sin));

        // ink auction
        uint mash = rmash(deal, pep, pop, pup);
        uint earn = rmul(tot / RAY, mash);

        // bill is the debt to attempt to cover when auctioning ink
        uint bill = rmul(chop, dtab / RAY);
        // clamp `sell` so bank only gets enough to underwrite urn.
        if (earn > bill) {
            sell = (urn.ink * bill) / earn;
            earn = bill;
        } else {
            sell = urn.ink;
        }

        vsync(earn, dtab / RAY);

        // update collateral balance
        unchecked {
            uint _ink = urn.ink -= sell;
            emit NewPalm1("ink", bytes32(bytes20(u)), bytes32(_ink));
        }

        // trade collateral with keeper for rico
        rico.burn(msg.sender, earn);
        risk.mint(msg.sender, sell);
    }

    // Update joy and possibly line. Workaround for stack too deep
    function vsync(uint earn, uint owed) internal {

        if (earn < owed) {
            // drop line value as precaution
            uint prev = line;
            uint loss = RAY * (owed - earn);
            uint next = loss > prev ? 0 : prev - loss;
            line = next;
            emit NewPalm0("line", bytes32(next));
        }

        // update joy to help cancel out sin
        uint mood = joy + earn;
        joy = mood;
        emit NewPalm0("joy", bytes32(mood));
    }

    // drip without flog
    function _drip() internal returns (uint _rack) {
        // multiply rack by fee every second
        uint prev = rack;

        if (block.timestamp == rho) return rack;

        // multiply rack by fee every second
        _rack = grow(prev, fee, block.timestamp - rho);

        // difference between current and previous rack determines interest
        uint256 delt = _rack - prev;
        uint256 rad  = tart * delt;
        uint256 all  = rest + rad;

        rho      = block.timestamp;
        emit NewPalm0("rho", bytes32(block.timestamp));

        rack     = _rack;
        emit NewPalm0("rack", bytes32(_rack));

        // tart * rack is a rad, interest is a wad, rest is the change
        rest      = all % RAY;
        emit NewPalm0("rest", bytes32(rest));

        joy       = joy + (all / RAY);
        emit NewPalm0("joy", bytes32(joy));
    }

    function keep() external payable _flog_ {
        _drip();

        // use equal scales for sin and joy
        uint _joy   = joy;
        uint _sin   = sin / RAY;

        // in case of deficit max price should always lead to decrease in way
        uint price = type(uint256).max;
        uint dt    = block.timestamp - bel;

        if (_joy > _sin) {

            // pay down sin, then auction off surplus RICO for RISK
            if (_sin > 1) {
                // gas - don't zero sin
                _joy = _heal(_sin - 1);
            }

            // price decreases with time
            price = grow(pex, dam, dt);

            // buy-and-burn risk with remaining (`flap`) rico
            uint flap  = rmul(_joy - 1, wel);
            uint earn  = rmul(flap, price);
            _joy      -= flap;
            joy        = _joy;
            emit NewPalm0("joy", bytes32(_joy));

            // swap rico for RISK, pay protocol fee
            rico.mint(msg.sender, flap);
            risk.burn(msg.sender, earn);
            wal -= earn;
            emit NewPalm0("wal", bytes32(wal));
        }
        bel = block.timestamp;
        emit NewPalm0("bel", bytes32(block.timestamp));
        poke(price, dt);
    }

    function _heal(uint wad) internal returns (uint _joy) {

        sin  = sin  - (wad * RAY);
        emit NewPalm0("sin", bytes32(sin));

        joy  = (_joy = joy - wad);
        emit NewPalm0("joy", bytes32(_joy));
    }

    // give msg.sender some RISK
    function mine() external _flog_ {
        uint elapsed = block.timestamp - phi;

        gif = grow(gif, mop, elapsed);
        emit NewPalm0("gif", bytes32(gif));

        phi = block.timestamp;
        emit NewPalm0("phi", bytes32(block.timestamp));

        uint flate = (gif + rmul(wal, lax)) * elapsed;
        risk.mint(msg.sender, flate);

        wal  += flate;
        emit NewPalm0("wal", bytes32(wal));
    }

    // price rate controller
    // ensures that market price (mar) roughly tracks par
    // note that price rate (way) can be less than 1
    // this is how the system achieves negative effective borrowing rates
    // if quantity rate is 1%/yr (fee > RAY) but price rate is -2%/yr (way < RAY)
    // borrowers are rewarded about 1%/yr for borrowing and shorting rico

    // poke par and way
    function poke(uint mar, uint dt) internal {
        if (dt == 0) return;

        // use previous `way` to grow `par` to keep par updates predictable
        uint _par = par;
        uint _way = way;
        _par      = grow(_par, _way, dt);
        par       = _par;
        emit NewPalm0("par", bytes32(_par));

        // lower the price rate (way) when mar > par or system is in deficit
        // raise the price rate when mar < par
        // this is how mar tracks par and rcs pays down deficits
        if (mar < _par) {
            _way = min(cap, grow(_way, how, dt));
        } else if (mar > _par) {
            _way = max(rinv(cap), grow(_way, rinv(how), dt));
        }

        way = _way;
        emit NewPalm0("way", bytes32(_way));
    }

}
