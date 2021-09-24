// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.8.6;

contract Ward {
    mapping (address => bool) public wards;
    event Ward(address indexed caller, address indexed trusts, bool bit);
    constructor() {
      wards[msg.sender] = true;
      emit Ward(msg.sender, msg.sender, true);
    }
    function rely(address usr) external auth {
      emit Ward(msg.sender, usr, true);
      wards[usr] = true;
    }
    function deny(address usr) external auth {
      emit Ward(msg.sender, usr, true);
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
