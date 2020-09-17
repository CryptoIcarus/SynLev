//////////////////////////////////////////////////
//SYNLEV PRICE AGGREGATOR CONTRACT V 0.1.0
//////////////////////////

pragma solidity >= 0.6.4;

import './ownable.sol';

interface AggregatorInterface {
  function latestAnswer() external view returns (int256);
  function latestTimestamp() external view returns (uint256);
  function latestRound() external view returns (uint256);
  function getAnswer(uint256 roundId) external view returns (int256);
  function getTimestamp(uint256 roundId) external view returns (uint256);

  event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);
  event NewRound(uint256 indexed roundId, address indexed startedBy, uint256 startedAt);
}


contract vaultPriceAggregator is Owned {

  constructor() public {

  }

  struct vaultStruct{
    AggregatorInterface ref;
    address refPropose;
    uint proposeTimestamp;
  }


  mapping(address => vaultStruct) public refVault;     //Vault address => vaultStruct

  uint256 public maxUpdates = 10;


  function priceRequestREAL(address vault, uint256 lastUpdated)
  public
  view
  returns(uint256[] memory, uint256)
  {
    uint256 currentRound = refVault[vault].ref.latestRound();
    if(currentRound > lastUpdated) {
      uint256 pricearrayLength = 1 + currentRound - lastUpdated;
      pricearrayLength = pricearrayLength > maxUpdates ? maxUpdates : pricearrayLength;
      uint256[] memory pricearray = new uint256[] (pricearrayLength);
      pricearray[0] =  uint256(refVault[vault].ref.getAnswer(lastUpdated));
      for(uint i = 1; i < pricearrayLength; i++) {
        pricearray[pricearrayLength - i] = uint256(refVault[vault].ref.getAnswer(1 + currentRound - i));
      }
      return(pricearray, currentRound);
    }
    else {
      return(new uint256[](0), lastUpdated);
    }
  }

  //FOR TESTING PURPOSES ONLY AS CHAINLINK HAS NOT BEEN ACTIVELY UPDATING ORACLE
  //DATA WE GO BACK IN TIME
  function priceRequest(address vault, uint256 lastUpdated)
  public
  view
  returns(uint256[] memory, uint256)
  {
    uint256 currentRound;
    if(lastUpdated == 0) {
      currentRound = 18446744073709552369;
    }
    else {
      currentRound = lastUpdated + block.timestamp % 5;
    }

    if(currentRound > lastUpdated) {
      uint256 pricearrayLength = 1 + currentRound - lastUpdated;
      pricearrayLength = pricearrayLength > maxUpdates ? maxUpdates : pricearrayLength;
      uint256[] memory pricearray = new uint256[] (pricearrayLength);
      pricearray[0] =  uint256(refVault[vault].ref.getAnswer(lastUpdated));
      for(uint i = 1; i < pricearrayLength; i++) {
        pricearray[pricearrayLength - i] = uint256(refVault[vault].ref.getAnswer(1 + currentRound - i));
      }
      return(pricearray, currentRound);
    }
    else {
      return(new uint256[](0), lastUpdated);
    }
  }



  function setMaxUpdates(uint256 amount) public onlyOwner() {
    require(amount > 1);
    maxUpdates = amount;
  }



  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~//
  //Functions setting and updating vault
  //to chainlink aggregator contract connections
  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~//

  //Can only be called by vault proxy, initiates pair
  function registerVaultAggregator(address aggregator) public {
    refVault[msg.sender].ref = AggregatorInterface(aggregator);
  }
  //Admin only propose new chainlink aggregator address
  function proposeVaultAggregator(address vault, address aggregator) public onlyOwner() {
    refVault[vault].refPropose = aggregator;
    refVault[vault].proposeTimestamp = block.timestamp;
  }
  function updateVaultAggregator(address vault) public {
    if(refVault[vault].refPropose != address(0) && refVault[vault].proposeTimestamp + 7 days <= block.timestamp) {
      refVault[msg.sender].ref = AggregatorInterface(refVault[vault].refPropose);
      refVault[vault].refPropose = address(0);
    }
  }



}
