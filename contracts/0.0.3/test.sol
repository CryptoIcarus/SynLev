pragma solidity >= 0.6.4;



contract test {
    using SafeMath for uint256;

    uint256 public multiplier = 3;
    uint256 public lossLimit = 9 * 10**17;
    uint256 public kControl = 15 * 10**8;
    uint256 public sbearEquity = 10**20;
    uint256 public sbullEquity = 10**20;

function updatePrice(uint256[] memory priceData, uint256 roundId) public returns(uint256, uint256, uint256, uint256) {
    uint256 bullEquity = sbullEquity;
    uint256 bearEquity = sbearEquity;
    uint256 totalEquity = bullEquity + bearEquity;
    uint256 movement;

    uint256 bearKFactor;
    uint256 bullKFactor;

    uint256 pricedelta;

    for (uint i = 1; i < priceData.length; i++) {
      bullKFactor = getKFactor(bullEquity, bullEquity, bearEquity, totalEquity);
      bearKFactor = getKFactor(bearEquity, bullEquity, bearEquity, totalEquity);
      //BEARISH MOVEMENT, CALC BULL DATA
      if(priceData[i-1] != priceData[i]) {
        if(priceData[i-1] > priceData[i]) {
          pricedelta = priceData[i-1].mul(10**18);
          pricedelta = pricedelta.div(priceData[i]);
          pricedelta = pricedelta.sub(10**18);
          pricedelta = pricedelta.mul(multiplier.mul(bullKFactor)).div(10**9);
          pricedelta = pricedelta < lossLimit ? pricedelta : lossLimit;
          movement = bullEquity.mul(pricedelta).div(10**18);
          bearEquity = bearEquity.add(movement);
          bullEquity = totalEquity.sub(bearEquity);
        }
        //BULLISH MOVEMENT
        else if(priceData[i-1] < priceData[i]) {
          pricedelta = priceData[i].mul(10**18);
          pricedelta = pricedelta.div(priceData[i-1]);
          pricedelta = pricedelta.sub(10**18);
          pricedelta = pricedelta.mul(multiplier.mul(bearKFactor)).div(10**9);
          pricedelta = pricedelta < lossLimit ? pricedelta : lossLimit;
          movement = bearEquity.mul(pricedelta).div(10**18);
          bullEquity = bullEquity.add(movement);
          bearEquity = totalEquity.sub(bullEquity);
        }
      }
    }




      uint256 bullPrice = bullEquity.mul(10**18).div(10**20);
      uint256 bearPrice = bearEquity.mul(10**18).div(10**20);

      //price[bull] = bullEquity.mul(10**18).div(IERC20(bull).totalSupply().add(liqTokens[bull]));
      //price[bear] = bearEquity.mul(10**18).div(IERC20(bear).totalSupply().add(liqTokens[bear]));

    return(bullEquity, bearEquity, bullPrice, bearPrice);
  }

    function getKFactor(uint256 equity, uint256 bullEquity, uint256 bearEquity, uint256 totalEquity)
    public
    view
    returns(uint256) {
    if(bullEquity  == 0 || bearEquity == 0) {
      return(0);
    }
    else {
      uint256 tokenEquity = equity;
      tokenEquity = tokenEquity > 0 ? tokenEquity : 1;
      uint256 kFactor = totalEquity.mul(10**9).div(tokenEquity.mul(2)) < kControl ? totalEquity.mul(10**9).div(tokenEquity.mul(2)): kControl;
      return(kFactor);
    }
  }


}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}
