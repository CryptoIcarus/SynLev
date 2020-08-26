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

interface AggregatorInterface {
  function latestAnswer() external view returns (int256);
  function latestTimestamp() external view returns (uint256);
  function latestRound() external view returns (uint256);
  function getAnswer(uint256 roundId) external view returns (int256);
  function getTimestamp(uint256 roundId) external view returns (uint256);

  event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);
  event NewRound(uint256 indexed roundId, address indexed startedBy, uint256 startedAt);
}


contract price_oracle_integrator is Context, Owned {

  constructor() public {

  }

  struct vaultStruct{
    AggregatorInterface ref;
    address refPropose;
    uint proposeTimestamp;
  }


  mapping(address => vaultStruct) public refVault;     //Vault address => vaultStruct


  function priceRequest(address vault, uint256 lastUpdated)
  public
  view
  returns(int256[] memory, uint256)
  {
    uint256 currentRound = refVault[vault].ref.latestRound();
    int256[] memory pricearray;
    if(currentRound > lastUpdated) {
      uint256 pricearrayLength = 1 + currentRound - lastUpdated;
      pricearray = new int256[] (pricearrayLength);
      for(uint i = 0; i < pricearrayLength; i++) {
        pricearray[i] = refVault[vault].ref.getAnswer(lastUpdated + i);
      }
      return(pricearray, currentRound);
    }
    else {
      return(new int256[](0), lastUpdated);
    }
  }





  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~//
  //Functions setting and updating vault
  //to chainlink aggregator contract connections
  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~//

  //Can only be called by vault contracts constructor, initiates pair
  function registerVaultAggregator(address aggregator) public {
    refVault[msg.sender].ref = AggregatorInterface(aggregator);
  }
  //Admin only propose new chainlink aggregator address
  function proposeVaultAggregator(address vault, address aggregator) public onlyOwner() {
    refVault[vault].refPropose = aggregator;
    refVault[vault].proposeTimestamp = block.timestamp;
  }
  function updateVaultAggregator(address vault) public {
    if(refVault[vault].refPropose != address(0) && refVault[vault].proposeTimestamp + 1 days <= block.timestamp) {
      refVault[msg.sender].ref = AggregatorInterface(refVault[vault].refPropose);
      refVault[vault].refPropose = address(0);
    }
  }



}
