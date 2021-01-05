//////////////////////////////////////////////////
//SYNLEV PRICE AGGREGATOR CONTRACT V 1.2
//////////////////////////

pragma solidity >= 0.6.6;

import './ownable.sol';
import './libraries/SafeMath.sol';
import './interfaces/AggregatorV2V3Interface.sol';
import './interfaces/vaultInterface.sol';

contract priceAggregator is Owned {
  using SafeMath for uint256;

  constructor() public {
    standardUpdateWindow = 10;
    refVault[0xFf40827Ee1c4Eb6052044101E1C6E28DBe1440e3].ref =
      AggregatorV2V3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    refVault[0xA81f8460dE4008577e7e6a17708102392f9aD92D].ref =
      AggregatorV2V3Interface(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
  }

  struct vaultStruct{
    AggregatorInterface ref;
    uint256 updateWindow;
  }

  mapping(address => vaultStruct) public refVault;     //Vault address => vaultStruct

  uint256 public standardUpdateWindow;

  function priceRequest(address vault, uint256 lastUpdated)
    public
    view
    returns(int256[] memory, uint256)
    {
      vaultStruct rVault = refVault[vault];
      uint256 currentRound = rVault.ref.latestRound();
      if(currentRound > lastUpdated) {
        int256[] memory pricearray = new int256[] (2);
        uint256 updateWindow = rVault.updateWindow != 0 ? rVault.updateWindow : standardUpdateWindow;
        pricearray[0] = rVault.getRoundData(lastUpdated).answer;
        for(uint i = 1; i < udpateWindow - 1; i++) {
          pricedata[1] = rVault.getRoundData(currentRound.sub(i)).answer;
        }
        pricearray[0] = pricearray[0].add(pricearray[1]);
        pricearray[1] = pricearray[1].add(rVault.getRoundData(currentRound).answer);
        pricearray[0] = pricearray[0].div(updateWindow);
        pricearray[0] = pricearray[1].div(updateWindow);
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

  function setStandardUpdateWindow(uint256 amount, vaultStruct vault) public onlyOwner() {
    require(amount >= 1);
    vaultStruct.updateWindow = amount;
  }

  function setStandardUpdateWindow(uint256 amount) public onlyOwner() {
    require(amount >= 1);
    standardUpdateWindow = amount;
  }

  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~//
  //Functions setting and updating vault
  //to chainlink aggregator contract connections
  //~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~//

  //Can only be called by vault proxy, initiates pair
  function registerVaultAggregator(address aggregator) public {
    refVault[msg.sender].ref = AggregatorV2V3Interface(aggregator);
  }
}
