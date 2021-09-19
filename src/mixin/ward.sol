// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.6;

contract Ward {
    mapping (address => bool) public wards;
    constructor() {
      wards[msg.sender] = true;
    }
    function rely(address usr) external auth {
      wards[usr] = true;
    }
    function deny(address usr) external auth {
      wards[usr] = false;
    }
    function ward(string memory reason) internal view {
      require(wards[msg.sender], reason);
    }
    function ward() internal view {
      ward('err-ward');
    }
    modifier auth { 
      ward('err-auth');
      _;
    }
}
