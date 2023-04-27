// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.19;

import '../../lib/feedbase/src/Feedbase.sol';
import '../../lib/feedbase/src/mixin/ward.sol';
import '../../lib/gemfab/src/gem.sol';
import '../mixin/lock.sol';
import '../mixin/flog.sol';
import '../vat.sol';
import '../flow.sol';
import './hook.sol';

contract ERC20Hook is Hook, Ward, Lock, Flog, Math {
    // per-auction urn identifier
    struct Sale {
        bytes32 ilk;
        address urn;
    }

    // per-ilk gem and price feed
    struct Item {
        address gem;   // this ilk's gem
        address fsrc;  // [obj] feedbase `src` address
        bytes32 ftag;  // [tag] feedbase `tag` bytes32
    }

    mapping (address gem => bool flashable) public pass;
    mapping (bytes32 ilk => Item) public items;
    mapping (uint256 aid => Sale) public sales;
    // collateral amounts
    mapping (bytes32 ilk => mapping(address usr => uint)) public inks;

    Feedbase    public feed;
    DutchFlower public flow;
    Gem         public rico;
    Vat         public vat;

    error ErrBigFlowback();
    error ErrMintCeil();
    error ErrLoanArgs();
    error ErrTransfer();
    error ErrDinkLength();

    constructor(address _feed, address _vat, address _flow, address _rico) {
        feed = Feedbase(_feed);
        flow = DutchFlower(_flow);
        rico = Gem(_rico);
        vat  = Vat(_vat);
    }

    function frobhook(
        address sender,
        bytes32 i,
        address u,
        bytes calldata _dink,
        int  // dart
    ) _ward_ _flog_ external returns (bool safer) {
        // read dink as a single uint
        address gem = items[i].gem;
        if (_dink.length != 32) revert ErrDinkLength();
        int dink = int(uint(bytes32(_dink)));
        inks[i][u] = add(inks[i][u], dink);
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
        return dink >= 0;
    }

    function grabhook(
        address vow,
        bytes32 i,
        address u,
        uint256, // art
        uint256 bill,
        address payable keeper
    ) _ward_ _flog_ external returns (uint aid) {
        uint ham = inks[i][u];
        inks[i][u] = 0;
        // flip the ink, try to get bill back
        aid = flow.flow(vow, items[i].gem, ham, address(rico), bill, keeper);
        sales[aid] = Sale({ ilk: i, urn: u });
    }

    function safehook(bytes32 i, address u) view public returns (uint, uint) {
        // total value of collateral = ink * price feed val
        Item storage item = items[i];
        (bytes32 val, uint ttl) = feed.pull(item.fsrc, item.ftag);
        return (uint(val) * inks[i][u], ttl);
    }

    function grant(address gem) _flog_ external {
        Gem(gem).approve(address(flow), type(uint).max);
    }

    function flowback(uint256 aid, uint refund) _ward_ _flog_ external {
        // frob refunded ink back into the urn
        if (refund == 0)  return;
        if (refund >= 2 ** 255) revert ErrBigFlowback();
        Sale storage sale = sales[aid];
        bytes32 ilk = sale.ilk;
        address urn = sale.urn;
        delete sales[aid];
        vat.frob(ilk, urn, abi.encodePacked(refund), 0);
    }

    function wire(bytes32 ilk, address gem, address fsrc, bytes32 ftag) _ward_ _flog_ external {
        items[ilk] = Item({
            gem : gem,
            fsrc: fsrc,
            ftag: ftag
        });
    }

    function flash(address[] calldata gems, uint[] calldata wads, address code, bytes calldata data)
      _lock_ _flog_ external returns (bytes memory result) {
        if (gems.length != wads.length) revert ErrLoanArgs();

        for(uint i = 0; i < gems.length; i++) {
            if (!pass[gems[i]]) revert ErrLoanArgs();
            if (!Gem(gems[i]).transfer(code, wads[i])) revert ErrTransfer();
        }

        bool ok;
        (ok, result) = code.call(data);
        require(ok, string(result));

        for(uint i = 0; i < gems.length; i++) {
            if (!Gem(gems[i]).transferFrom(code, address(this), wads[i])) revert ErrTransfer();
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
