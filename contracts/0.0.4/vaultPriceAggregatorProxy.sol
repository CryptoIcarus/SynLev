//////////////////////////////////////////////////
//SYNLEV PRICE AGGREGATOR PROXY CONTRACT V 0.0.4
//////////////////////////

pragma solidity >= 0.6.4;


interface vaultPriceAggregatorInterface {
  function priceRequest(address vault, uint256 lastUpdated) external view returns(uint256[] memory, uint256);
}

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

contract vaultPriceAggregatorProxy is Context, Owned {

  vaultPriceAggregatorInterface public vaultPriceAggregator;
  address public vaultPriceAggregatorPropose;
  uint256 public proposeTimestamp;

  function priceRequest(address vault, uint256 lastUpdated)
  public
  view
  virtual
  returns(uint256[] memory, uint256) {

    (uint256[] memory priceData, uint256 roundID) =
    vaultPriceAggregator.priceRequest(vault, lastUpdated);

    return(priceData, roundID);
  }




  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~//
  //Functions setting and updating vault price aggregator
  //1 day delay required to push update
  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~//
  function setVaultPriceAggregator(address account) public onlyOwner() {
    vaultPriceAggregator = vaultPriceAggregatorInterface(account);
  }

  function proposeVaultPriceAggregator(address account) public onlyOwner() {
    vaultPriceAggregatorPropose = account;
    proposeTimestamp = block.timestamp;
  }
  function updateVaultAggregator() public {
    if(vaultPriceAggregatorPropose != address(0) && proposeTimestamp + 1 days <= block.timestamp) {
      vaultPriceAggregator = vaultPriceAggregatorInterface(vaultPriceAggregatorPropose);
      vaultPriceAggregatorPropose = address(0);
    }
  }

}
