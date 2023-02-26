// SPDX-License-Identifier: AGPL-3.0-or-later

// Stub contract for testing public `Math` functions. This is necessary because
// we are avoiding the use of 'libraries' and instead want to test those public
// functions that are compiled into JUMP destinations instead of DELEGATECALLS.

pragma solidity 0.8.18;

import './math.sol';

contract MathStub is Math {
    uint256 public constant _BLN = 10 **  9;
    uint256 public constant _WAD = 10 ** 18;
    uint256 public constant _RAY = 10 ** 27;

    function _min(uint256 x, uint256 y) public pure returns (uint256 z) {
        return min(x, y);
    }

    function _add(uint256 x, int256 y) public pure returns (uint256 z) {
        return add(x, y);
    }

    function _wmul(uint256 x, uint256 y) public pure returns (uint256 z) {
        return wmul(x, y);
    }
    function _wdiv(uint256 x, uint256 y) public pure returns (uint256 z) {
        return wdiv(x, y);
    }

    function _rmul(uint256 x, uint256 y) public pure returns (uint256 z) {
      return rmul(x, y);
    }
    function _rdiv(uint256 x, uint256 y) public pure returns (uint256 z) {
      return rdiv(x, y);
    }
    function _rpow(uint256 x, uint256 n) public pure returns (uint256 z) {
      return rpow(x, n);
    }

    function _grow(uint256 amt, uint256 ray, uint256 dt) public pure returns (uint256 z) {
      return grow(amt, ray, dt);
    }
}
