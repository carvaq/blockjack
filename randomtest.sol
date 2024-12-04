//SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.7;

contract RandomNumber {
  uint randNo = 0;
   function setNumber() external {
        randNo= uint (keccak256(abi.encodePacked (msg.sender, block.timestamp, randNo)));
     }
    function getNumber() external view returns (uint) {
    return randNo;
     }
     function getRandomNumber() external view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp)));
    }
}