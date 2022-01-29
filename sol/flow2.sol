pragma solidity 0.8.9;

interface Flow {
  function flip(Flowback back, address gin, address gout, uint ink, uint bill) external returns (bytes32);
  function flap(Flowback back, address gin, address gout, uint surplus) external returns (bytes32);
  function flop(Flowback back, address gin, address gout, uint deficit) external returns (bytes32);
}

interface Flowback {
  function flipback(bytes32 aid, bool last, uint proceeds) external;  // partial plop
  function flapback(bytes32 aid, bool last, uint proceeds) external;  // partial surplus sale
  function flopback(bytes32 aid, bool last, uint request) external;   // yank
}
