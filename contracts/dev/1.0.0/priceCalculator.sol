//////////////////////////////////////////////////
//SYNLEV VAULT CONTRACT V 0.1.0
//////////////////////////

pragma solidity >= 0.6.6;

import './ownable.sol';
import './libraries/SafeMath.sol';
import './libraries/SignedSafeMath.sol';
import './interfaces/vaultInterface.sol'
import './interfaces/priceAggregator.sol'

contract priceCalculator is Owned {
  using SafeMath for uint256;
  using SignedSafeMath for int256;

  constructor() public {
    lossLimit = 9 * 10**8;
    kControl = 15 * 10**8;
    priceProxy = priceAggregatorProxy(0);
  }

  uint256 public lossLimit;
  uint256 public kControl;
  priceAggregatorProxy public priceProxy;

  /*
   * @notice Calculates the most recent price data.
   * @dev If there is no new price data it returns current price/equity data.
   * Safety checks are done by SynLev price aggregator. All calcualtions done
   * via equity in ETH, not price to avoid rounding errors. Caculates price
   * based on the "losing side", then subracts from the other. Mitigates a
   * prefrence in rounding error to either bull or bear tokens.
   * TODO Check if more gas efficient to create two separate functions to get k
   * values.
   * TODO Migrate grabbing current equity variables to after token equity check
   * for potential gas savings
   */
  function getUpdatedPrice(address vault, uint256 roundId)
  public
  view
  returns(
    uint256 rBullPrice,
    uint256 rBearPrice,
    uint256 rBullLiqEquity,
    uint256 rBearLiqEquity,
    uint256 rBullEquity,
    uint256 rBearEquity,
    uint256 rRoundId
  ) {
    //Requests price data from price aggregator proxy
    (
      int256[] memory priceData,
      uint256 roundId
    ) = priceProxy.priceRequest(address(this), latestRoundId);
    vaultInterface ivault = vaultInterface(vault);
    address bull = ivault.getBullToken();
    address bear = ivault.getBearToken();
    //Only update if price data if price array contains 2 or more values
    //If there is no new price data pricedate array will have 0 length
    if(priceData.length > 0) {
      //Only update if there is soome bull/bear equity
      uint256 multiplier = ivault.getMultiplier();
      uint256 bullEquity = ivault.getTokenEquity(bull);
      uint256 bearEquity = ivault.getTokenEquity(bear);
      if(bullEquity != 0 && bearEquity != 0) {
        uint256 totalEquity = ivault.getTotalEquity();
        //Declare varialbes for keeping track of price durring calcualtions
        uint256 movement;
        uint256 bearKFactor;
        uint256 bullKFactor;
        uint256 pricedelta;
        for (uint i = 1; i < priceData.length; i++) {
          //Grab k factor based on running equity
          bullKFactor = getKFactor(bullEquity, bullEquity, bearEquity, totalEquity);
          bearKFactor = getKFactor(bearEquity, bullEquity, bearEquity, totalEquity);
          if(priceData[i-1] != priceData[i]) {
            //Bearish movement, calc equity from the perspective of bull
            if(priceData[i-1] > priceData[i]) {
              //Treats 0 price value as 1, 0 causes divides by 0 error
              if(priceData[i-1] == 0) priceData[i-1] = 1;
              //Gets price change in absolute terms.
              //Handles possible negative price data
              pricedelta = priceData[i-1] > 0 ?
                uint256(priceData[i-1].sub(priceData[i]).mul(1 gwei).div(priceData[i-1])) :
                uint256(-priceData[i-1].sub(priceData[i]).mul(1 gwei).div(priceData[i-1]));
              //Converts price change to be in terms of bull equity change
              //As a percentage
              pricedelta = pricedelta.mul(multiplier.mul(bullKFactor)).div(1 gwei);
              //Dont allow loss to be greater than set loss limit
              pricedelta = pricedelta < lossLimit ? pricedelta : lossLimit;
              //Calculate equity loss of bull equity
              movement = bullEquity.mul(pricedelta).div(1 gwei);
              //Adds equity movement to running bear euqity and removes that
              //Loss from running bull equity
              bearEquity = bearEquity.add(movement);
              bullEquity = totalEquity.sub(bearEquity);
            }
            //Bullish movement, calc equity from the perspective of bear
            //Same process as above. only from bear perspective
            else if(priceData[i-1] < priceData[i]) {
              if(priceData[i] == 0) priceData[i] = 1;
              pricedelta = priceData[i] > 0 ?
                uint256(priceData[i].sub(priceData[i-1]).mul(1 gwei).div(priceData[i-1])) :
                uint256(-priceData[i].sub(priceData[i-1]).mul(1 gwei).div(priceData[i-1]));
              pricedelta = pricedelta.mul(multiplier.mul(bearKFactor)).div(1 gwei);
              pricedelta = pricedelta < lossLimit ? pricedelta : lossLimit;
              movement = bearEquity.mul(pricedelta).div(1 gwei);
              bullEquity = bullEquity.add(movement);
              bearEquity = totalEquity.sub(bullEquity);
            }
          }
        }
        return(
          bullEquity.mul(1 ether).div(IERC20(bull).totalSupply().add(ivault.getLiqTokens(bull))),
          bearEquity.mul(1 ether).div(IERC20(bear).totalSupply().add(ivault.getLiqTokens(bear))),
          price[bull].mul(ivault.getLiqTokens(bull)).div(1 ether),
          price[bear].mul(ivault.getLiqTokens(bear)).div(1 ether),
          bullEquity.sub(ivault.getLiqEquity(bull)),
          bearEquity.sub(ivault.getLiqEquity(bear)),
          roundId,
          true
        );
      }
    }
    else {
      return(
        ivault.getPrice(bull),
        ivault.getPrice(bear),
        ivault.getLiqEquity(bull),
        ivault.getLiqEquity(bear),
        ivault.getTokenEquity(bull),
        ivault.getTokenEquity(bear),
        roundId,
        false);
    }
  }

  /*
   * @notice Calculates k factor of selected token. K factor is the multiplier
   * that adjusts the leverage level to maintain 100% liquidty at all times.
   * @dev K factor is scaled 10^9. A K factor of 1 represents a 1:1 ratio of
   * bull and bear equity.
   * @param targetEquity The total euqity of the target bull token
   * @param bullEquity The total equity bull tokens
   * @param bearEquity The total equity bear tokens
   * @param totalEquity The total equity of bull and bear tokens
   * @return K factor
   * TODO Check if neccesary to do divides by 0 check
   */
  function getKFactor(uint256 targetEquity, uint256 bullEquity, uint256 bearEquity, uint256 totalEquity)
  public
  view
  returns(uint256) {
    //If either token has 0 equity k value is 0
    if(bullEquity  == 0 || bearEquity == 0) {
      return(0);
    }
    else {
      //Avoids divides by 0 error
      targetEquity = targetEquity > 0 ? targetEquity : 1;
      uint256 kFactor =
        totalEquity.mul(10**9).div(targetEquity.mul(2)) < kControl ?
        totalEquity.mul(10**9).div(targetEquity.mul(2)): kControl;
      return(kFactor);
    }
  }

  ///////////////////
  //ADMIN FUNCTIONS//
  ///////////////////
  function setLossLimit(uint256 amount) public onlyOwner() {
    lossLimit = amount;
  }
  function setkControl(uint256 amount) public onlyOwner() {
    kControl = amount;
  }
  function setPriceProxy(address proxy) public onlyOwner() {
    priceProxy = priceAggregatorProxy(proxy);
  }
}
