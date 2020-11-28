//////////////////////////////////////////////////
//SYNLEV PRICE AGGREGATOR CONTRACT V 1.0.0
//////////////////////////

pragma solidity >= 0.6.6;

import './ownable.sol';
import './libraries/SafeMath.sol';
import './interfaces/AggregatorInterface.sol';
import './interfaces/vaultInterface.sol';

contract priceAggregator is Owned {
  using SafeMath for uint256;

  constructor() public {
    refVault[0xFf40827Ee1c4Eb6052044101E1C6E28DBe1440e3].ref =
      AggregatorInterface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
  }

  struct vaultStruct{
    AggregatorInterface ref;
  }

  mapping(address => vaultStruct) public refVault;     //Vault address => vaultStruct

  uint256 public maxUpdates = 50;

  function priceRequest(address vault, uint256 lastUpdated)
  public
  view
  returns(int256[] memory, uint256)
  {
    uint256 currentRound = refVault[vault].ref.latestRound();
    if(currentRound > lastUpdated) {
      int256 initialPrice = refVault[vault].ref.getAnswer(lastUpdated);
      uint256 pricearrayLength;
      uint16 phaseId = refVault[vault].ref.phaseId();
      if(uint16(lastUpdated >> 64) < phaseId) {
        lastUpdated = uint256(phaseId) * 2**64 + 1;
        pricearrayLength = currentRound.add(2).sub(lastUpdated);
      }
      else {
        pricearrayLength = currentRound.add(1).sub(lastUpdated);
      }
      pricearrayLength = pricearrayLength > maxUpdates ?
      maxUpdates : pricearrayLength;
      int256[] memory pricearray = new int256[] (pricearrayLength);
      pricearray[0] = initialPrice;
      for(uint i = 1; i < pricearrayLength; i++) {
        pricearray[pricearrayLength.sub(i)] =
        refVault[vault].ref.getAnswer(currentRound.add(1).sub(i));
      }
      return(pricearray, currentRound);
    }
    else {
      return(new int256[](0), currentRound);
    }
  }

  /*
   * @notice Returns false if the price is not updated on vault.
  */

  function roundIdCheck(address vault) public view returns(bool) {
    if(vaultInterface(vault).getLatestRoundId()
    < refVault[vault].ref.latestRound()) {
      return(false);
    }
    else return(true);
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
}
