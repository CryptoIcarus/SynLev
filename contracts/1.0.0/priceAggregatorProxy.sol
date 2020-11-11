//////////////////////////////////////////////////
//SYNLEV price aggregator proxy contract V 1.0.0
//////////////////////////

pragma solidity >= 0.6.4;

import './ownable.sol';
import './interfaces/priceAggregatorInterface.sol';

contract priceAggregatorProxy is Owned {

  constructor() public {
    priceAggregator = priceAggregatorInterface();
    proposeDelay = 7 days;
  }

  priceAggregatorInterface public priceAggregator;
  address public priceAggregatorPropose;
  address public priceAggregatorProposeTimestamp;

  uint256 public proposeDelay;
  uint256 public proposeDelayPropose;
  uint256 public proposeDelayTimestamp;

  function priceRequest(address vault, uint256 lastUpdated)
  public
  view
  virtual
  returns(int256[] memory, uint256) {

    (int256[] memory priceData, uint256 roundID) =
    priceAggregator.priceRequest(vault, lastUpdated);

    return(priceData, roundID);
  }

  function roundIdCheck(address vault) public view returns(bool) {
    return(priceAggregator.roundIdCheck(vault));
  }

  //Admin Functions
  function proposeVaultPriceAggregator(address account) public onlyOwner() {
    priceAggregatorPropose = account;
    priceAggregatorProposeTimestamp = block.timestamp;
  }
  function updateVaultPriceAggregator() public onlyOwner() {
    require(priceAggregatorPropose != 0);
    require(priceAggregatorProposeTimestamp + proposeDelay <= block.timestamp);
    priceAggregator = priceAggregatorInterface(priceAggregatorPropose);
    priceAggregatorPropose = address(0);
  }

  function proposeProposeDelay(uint256 delay) public onlyOwner() {
    proposeDelayPropose = delay;
    proposeDelayTimestamp = block.timestamp;
  }
  function updateProposeDelay() public onlyOwner() {
    require(proposeDelayPropose != 0);
    require(proposeDelayTimestamp + proposeDelay <= block.timestamp);
    proposeDelay = proposeDelayPropose;
    proposeDelayPropose = 0;
  }
}
