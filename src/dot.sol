// SPDX-License-Identifier: AGPL-3.0-or-later

/// dot.sol -- Reference Basket Calculator

pragma solidity 0.8.6;

import './mixin/math.sol';

interface Feedbase {
}

contract Dot is Math {
  Feedbase  public fb;
  struct Dat {
    address src;
    bytes32 tag;
    bytes32 val;
    uint256 ttl;
  }
  Dat[] public ps;
  Dat[] public qs;
  function dot() public returns (uint) {
    uint sum = 0;
    for(uint i = 0; i < ps.length; i++) {
      uint p = uint(ps[i].val);
      uint q = uint(qs[i].val);
      uint prod = wmul(p, q);
      sum += prod;
    }
    return sum;
  }
}


