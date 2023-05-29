// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.19;

import { Math } from '../mixin/math.sol';
import { Flog } from '../mixin/flog.sol';
import { Lock } from '../mixin/lock.sol';
import { Ward } from '../../lib/feedbase/src/mixin/ward.sol';
import { Gem } from '../../lib/gemfab/src/gem.sol';
import { Feedbase } from '../../lib/feedbase/src/Feedbase.sol';

import { Vat } from '../vat.sol';
import { Hook } from './hook.sol';

uint256 constant NO_CUT = type(uint256).max;

contract ERC20Hook is Hook, Ward, Lock, Flog, Math {
    // per-ilk gem and price feed
    struct Item {
        address gem;   // this ilk's gem
        address fsrc;  // [obj] feedbase `src` address
        bytes32 ftag;  // [tag] feedbase `tag` bytes32
    }

    mapping (address gem => bool flashable) public pass;
    mapping (bytes32 ilk => Item) public items;
    // collateral amounts
    mapping (bytes32 ilk => mapping(address usr => uint)) public inks;

    error ErrOutDated();
    error ErrLoanArgs();
    error ErrTransfer();
    error ErrDinkSize();

    address internal immutable self = address(this);

    Feedbase    public feed;
    address     public rico;
    Vat         public vat;

    constructor(address _feed, address _vat, address _rico) {
        feed = Feedbase(_feed);
        rico = _rico;
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
        if (_dink.length != 32) revert ErrDinkSize();
        int dink = int(uint(bytes32(_dink)));
        inks[i][u] = add(inks[i][u], dink);
        if (sender != self) {
            if (dink > 0) {
                if (!Gem(gem).transferFrom(sender, self, uint(dink))) {
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
        address keeper,
        uint256 rush,
        uint256 cut
    ) _ward_ _flog_ external {
        inks[i][u] -= flow(vow, i, inks[i][u], rico, bill, keeper, self, rush, cut);
    }

    function flow(address vow, bytes32 i, uint ham, address wag, uint wam, address keeper, address from, uint rush, uint cut
    ) _ward_ public returns (uint sell) {
        Item storage item = items[i];
        uint earn;
        if (cut == NO_CUT) {
            (bytes32 val, uint ttl) = feed.pull(item.fsrc, item.ftag);
            if (ttl < block.timestamp) revert ErrOutDated();
            cut = ham * uint(val);
        }
        // cut is RAD, rush is RAY, so vow earns a WAD
        earn = cut / rush;
        sell = ham;
        if (earn > wam) {
            sell = wam * ham / earn;
            earn = wam;
        }
        if (!Gem(wag).transferFrom(keeper, vow, earn)) revert ErrTransfer();
        if (from == self) {
            if (!Gem(item.gem).transfer(keeper, sell)) revert ErrTransfer();
        } else {
            if (!Gem(item.gem).transferFrom(from, keeper, sell)) revert ErrTransfer();
        }
    }

    function safehook(bytes32 i, address u) view public returns (uint, uint) {
        // total value of collateral = ink * price feed val
        Item storage item = items[i];
        (bytes32 val, uint ttl) = feed.pull(item.fsrc, item.ftag);
        return (uint(val) * inks[i][u], ttl);
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
            if (!Gem(gems[i]).transferFrom(code, self, wads[i])) revert ErrTransfer();
        }
    }

    function list(address gem, bool bit)
      _ward_ _flog_ external
    {
        pass[gem] = bit;
    }

}
