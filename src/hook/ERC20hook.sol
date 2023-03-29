// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.19;

import '../mixin/ward.sol';
import '../mixin/lock.sol';
import '../mixin/flog.sol';
import '../vat.sol';
import '../flow.sol';
import '../../lib/gemfab/src/gem.sol';

contract ERC20Hook is Ward, Lock, Flog {
    DutchFlower public flow;
    Vat public vat;
    Gem public rico;
    mapping(bytes32=>address) public gems;
    mapping (address gem => bool) public pass;
    uint256 public constant MINT = 2**140;

    struct Sale {
        bytes32 ilk;
        address urn;
    }

    mapping(uint256 aid => Sale) public sales;

    error ErrBigFlowback();
    error ErrMintCeil();
    error ErrLoanArgs();
    error ErrTransfer();
    error ErrWrongKey();

    constructor(address _vat, address _flow, address _rico) {
        vat = Vat(_vat);
        flow = DutchFlower(_flow);
        rico = Gem(_rico);
    }

    function frobhook(
        address sender,
        bytes32 i,
        address, // u
        int dink,
        int      // dart
    ) _ward_ _flog_ external {
        address gem = gems[i];
        if (sender != address(this)) {
            if (dink > 0) {
                if (!Gem(gem).transferFrom(sender, address(this), uint(dink))) {
                    revert ErrTransfer();
                }
            } else if (dink < 0) {
                if (!Gem(gem).transfer(sender, uint(-dink))) {
                    revert ErrTransfer();
                }
            }
        }
    }

    function grabhook(
        address vow,
        bytes32 i,
        address u,
        uint256 ink,
        uint256, // art
        uint256 bill,
        address payable keeper
    ) _ward_ _flog_ external returns (uint aid) {
        aid = flow.flow(vow, gems[i], ink, address(rico), bill, keeper);
        sales[aid] = Sale({ ilk: i, urn: u });
    }

    function grant(address gem) _flog_ external {
        Gem(gem).approve(address(flow), type(uint).max);
    }

    function flowback(uint256 aid, uint refund) _ward_ _flog_ external {
        if (refund == 0)  return;
        if (refund >= 2 ** 255) revert ErrBigFlowback();
        Sale storage sale = sales[aid];
        bytes32 ilk = sale.ilk;
        address urn = sale.urn;
        delete sales[aid];
        vat.frob(ilk, urn, int(refund), 0);
    }

    function link(bytes32 ilk, address gem) _ward_ _flog_ external {
        gems[ilk] = gem;
    }

    function flash(address[] calldata gs, uint[] calldata wads, address code, bytes calldata data)
      _lock_ _flog_ external returns (bytes memory result) {
        if (gs.length != wads.length) revert ErrLoanArgs();
        bool[] memory tags = new bool[](gs.length);
        bool lent;
        bool ok;

        for(uint i = 0; i < gs.length; i++) {
            if (pass[gs[i]]) {
                tags[i] = true;
                if (!Gem(gs[i]).transfer(code, wads[i])) revert ErrTransfer();
            } else {
                if (wads[i] > MINT || lent) revert ErrMintCeil();
                lent = true;
                Gem(gs[i]).mint(code, wads[i]);
            }
        }

        (ok, result) = code.call(data);
        require(ok, string(result));

        for(uint i = 0; i < gs.length; i++) {
            if (tags[i]) {
                if (!Gem(gs[i]).transferFrom(code, address(this), wads[i])) revert ErrTransfer();
            } else {
                Gem(gs[i]).burn(code, wads[i]);
            }
        }
    }

    function pair(address gem, bytes32 key, uint val) _ward_ _flog_ external {
        flow.curb(gem, key, val);
    }

    function list(address gem, bool bit)
      _ward_ _flog_ external
    {
        pass[gem] = bit;
    }

}
