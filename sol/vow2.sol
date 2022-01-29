pragma solidity 0.8.9;

import { Flow, Flowback } from './flow2.sol';
import { VatLike, GemLike, JoinLike } from './abi.sol';
import { Math } from './mixin/math.sol';
import { Ward } from './mixin/ward.sol';

contract Vow2 is Flowback, Math, Ward {
    Flow     public flow;
    JoinLike public join;
    address  public RISK;
    address  public RICO;
    address  public immutable self = address(this);

    struct Plop {
      address vat;
      bytes32 ilk;
      address urn;

      uint256 bill;
      uint256 paid;
    }
    // aid -> plop (flipback)
    mapping(bytes32=>Plop) public plops;

    function keep() external {
        uint surplus; uint deficit;
        if (surplus > 0) {
            flow.flap(this, RICO, RISK, surplus); // discard aid, we dont care
        } else if (deficit > 0) {
            flow.flop(this, RICO, RISK, surplus); // discard aid, we dont care
        }
    }

    function bail(address vat, bytes32 ilk, address urn) external {
        require(  ! VatLike(vat).safe(ilk, urn), 'ERR_SAFE' );
        (uint ink, uint art) = VatLike(vat).urns(ilk, urn);
        uint bill = VatLike(vat).grab(ilk, urn, self, self, -int(ink), -int(art));
        address gem = join.exit(address(vat), ilk, self, ink);
        bytes32 aid = flow.flip(this, gem, RICO, ink, bill);
        plops[aid] = Plop({ vat: vat, ilk: ilk, urn: urn, bill: bill, paid: 0 });
    }

    function flipback(bytes32 aid, bool last, uint proceeds) external
      _ward_ {
        Plop storage plop = plops[aid];
        plop.paid += proceeds;
        if (plop.paid < plop.bill) {
            VatLike(plop.vat).heal(proceeds);
        } else {
            uint extra = plop.paid - plop.bill;
            if ( extra < proceeds ) {
                uint refund = max(proceeds, extra);
                join.join(plop.vat, plop.ilk, plop.urn, refund);
                VatLike(plop.vat).heal(proceeds - refund);
            } else {
                join.join(plop.vat, plop.ilk, plop.urn, proceeds);
            }
        }
        if (last) {
            delete plops[aid];
        }
    }

    function flapback(bytes32 aid, bool last, uint proceeds) external
      _ward_ {
        GemLike(RISK).burn(msg.sender, proceeds);
    }

    function flopback(bytes32 aid, bool last, uint request) external
      _ward_ {
        GemLike(RISK).mint(msg.sender, request);
    }

    function link(bytes32 key, address val) external
      _ward_ {
             if (key == "flow") { flow = Flow(val); }
        else if (key == "join") { join = JoinLike(val); }
        else if (key == "RISK") { RISK = val; }
        else if (key == "RICO") { RICO = val; }
        else revert("ERR_LINK_KEY");
    }

}
