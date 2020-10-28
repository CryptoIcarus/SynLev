//////////////////////////////////////////////////
//SYNLEV price calculator proxy V 1.0.0
//////////////////////////

pragma solidity >= 0.6.4;

import './ownable.sol';
import './interfaces/priceCalculatorInterface.sol';

contract priceCalculatorProxy is Owned {

  priceCalculatorInterface public priceCalculator;
  address public priceCalculatorPropose;
  uint256 public proposeTimestamp;

  function getUpdatedPrice(address vault, uint256 latestRoundId)
  public
  view
  virtual
  returns(
    uint256[6] memory latestPrice,
    uint256 rRoundId,
    bool updated
  ) {

    return(priceCalculator.getUpdatedPrice(vault, latestRoundId));
  }


  //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  //FOR TESTING ONLY. REMOVE ON PRODUCTION
  //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  function setVaultPriceAggregator(address account) public onlyOwner() {
    priceCalculator = priceCalculatorInterface(account);
  }

  function proposeVaultPriceAggregator(address account) public onlyOwner() {
    priceCalculatorPropose = account;
    proposeTimestamp = block.timestamp;
  }
  function updateVaultAggregator() public {
    if(priceCalculatorPropose != address(0) && proposeTimestamp + 1 days <= block.timestamp) {
      priceCalculator = priceCalculatorInterface(priceCalculatorPropose);
      priceCalculatorPropose = address(0);
    }
  }

}
