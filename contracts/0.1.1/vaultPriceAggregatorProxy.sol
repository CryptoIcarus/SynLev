//////////////////////////////////////////////////
//SYNLEV PRICE AGGREGATOR PROXY CONTRACT V 0.1.0
//////////////////////////

pragma solidity >= 0.6.4;

import './ownable.sol';

interface vaultPriceAggregatorInterface {
  function priceRequest(address vault, uint256 lastUpdated) external view returns(int256[] memory, uint256);
}

contract vaultPriceAggregatorProxy is Owned {

  vaultPriceAggregatorInterface public vaultPriceAggregator;
  address public vaultPriceAggregatorPropose;
  uint256 public proposeTimestamp;

  function priceRequest(address vault, uint256 lastUpdated)
  public
  view
  virtual
  returns(int256[] memory, uint256) {

    (int256[] memory priceData, uint256 roundID) =
    vaultPriceAggregator.priceRequest(vault, lastUpdated);

    return(priceData, roundID);
  }




  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~//
  //Functions setting and updating vault price aggregator
  //1 day delay required to push update
  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~//


  //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  //FOR TESTING ONLY. REMOVE ON PRODUCTION
  //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
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
