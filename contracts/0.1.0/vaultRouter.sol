//////////////////////////////////////////////////
//SYNLEV ROUTER CONTRACT V 0.1.0
//////////////////////////

pragma solidity >= 0.6.4;

contract Context {
  constructor () internal { }
  function _msgSender() internal view virtual returns (address payable) {
    return msg.sender;
  }
  function _msgData() internal view virtual returns (bytes memory) {
    this;
    return msg.data;
  }
}

contract Owned {
  address public owner;
  address public newOwner;

  event OwnershipTransferred(address indexed _from, address indexed _to);

  constructor() public {
    owner = msg.sender;
  }

  modifier onlyOwner {
    require(msg.sender == owner);
    _;
  }

  function transferOwnership(address _newOwner) public onlyOwner {
    newOwner = _newOwner;
  }
  function acceptOwnership() public {
    require(msg.sender == newOwner);
    emit OwnershipTransferred(owner, newOwner);
    owner = newOwner;
    newOwner = address(0);
  }
}


contract vaultRouter is Context, Owned {



  function buyExactEthBullTokens(address vault, uint256 amount, uint256 deadline) public {
    //TODO
  }
  function buyExactBullTokens(address vault, uint256 amount, uint256 deadline) public {
    //TODO
  }
  function sellBullTokens(address vault, uint256 amount, uint256 deadline) public {
    //TODO
  }
  function buyExactEthBearTokens(address vault, uint256 amount, uint256 deadline) public {
    //TODO
  }
  function buyExactBearTokens(address vault, uint256 amount, uint256 deadline) public {
    //TODO
  }
  function sellBearTokens(address vault, uint256 amount, uint256 deadline) public {
    //TODO
  }








}
