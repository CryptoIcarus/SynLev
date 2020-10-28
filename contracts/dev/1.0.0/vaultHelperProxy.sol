//////////////////////////////////////////////////
//SYNLEV Vault Helper contract V 1.0.0
//////////////////////////

pragma solidity >= 0.6.4;

import './ownable.sol';
import './interfaces/vaultHelperInterface.sol'

contract vaultHelperProxy is Owned {

  vaultHelperInterface public vaultHelper;
  address public vaultHelperPropose;
  uint256 public proposeTimestamp;

  function getBonus(address vault, address token, uint256 eth)
  public
  view
  virtual
  returns(uint256) {
    return(vaultHelper.getBonus(vault, token, eth));
  }

  function getPenalty(address vault, address token, uint256 eth)
  public
  view
  virtual
  returns(uint256) {
    return(vaultHelper.getPenalty(vault, token, eth));
  }

  function getSharePrice(address vault)
  public
  view
  virtual
  returns(uint256) {
    return(vaultHelper.getSharePrice(vault));
  }

  function getLiqAddTokens(address vault, uint256 eth)
  public
  view
  virtual
  returns(
    uint256 bullEquity,
    uint256 bearEquity,
    uint256 bullTokens,
    uint256 bearTokens
  ) {
    return(vaultHelper.getLiqAddTokens(vault, eth));
  }

  function getLiqRemoveTokens(address vault, uint256 eth)
  public
  view
  virtual
  returns(
    uint256 bullEquity,
    uint256 bearEquity,
    uint256 bullTokens,
    uint256 bearTokens,
    uint256 feesPaid
  ) {
    return(vaultHelper.getLiqRemoveTokens(vault, eth));
  }

  //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  //FOR TESTING ONLY. REMOVE ON PRODUCTION
  //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
  function setVaultHelper(address account) public onlyOwner() {
    vaultHelper = vaultHelperInterface(account);
  }

  function proposeVaultPriceAggregator(address account) public onlyOwner() {
    vaultHelperPropose = account;
    proposeTimestamp = block.timestamp;
  }
  function updateVaultAggregator() public {
    if(vaultHelperPropose != address(0) && proposeTimestamp + 1 days <= block.timestamp) {
      vaultHelper = vaultHelperInterface(vaultHelperPropose);
      vaultHelperPropose = address(0);
    }
  }

}
