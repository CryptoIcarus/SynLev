pragma solidity >= 0.6.4;



contract test {
  using SafeMath for uint256;

  event PriceUpdate(
    uint256 roundId,
    uint256 bullPrice,
    uint256 bearPrice
  );
  event TokenBuy(
    address account,
    address token,
    uint256 tokensMinted,
    uint256 ethin,
    uint256 fees,
    uint256 bonus
  );
  event TokenSell(
    address account,
    address token,
    uint256 tokensBurned,
    uint256 ethout,
    uint256 fees,
    uint256 penalty
  );
  event LiquidityAdd(
    address account,
    uint256 eth,
    uint256 shares,
    uint256 shareprice
  );
  event LiquidityRemove(
    address account,
    uint256 eth,
    uint256 shares,
    uint256 shareprice
  );

  address public bull = address(0);
  address public bear = address(1);

  uint256 constant public multiplier = 3;
  uint256 public lossLimit = 9 * 10**8;
  uint256 public minBuy = 0;
  uint256 public kControl = 15 * 10**8;
  uint256 public balanceEquity;
  uint256 public balanceControlFactor = 10**9;

  uint256 public buyFee = 4 * 10**6;
  uint256 public sellFee = 4 * 10**6;
  address payable constant public feeRecipientProxy = address(2);  //Put proxy address (will chain fallback functions)


  uint256 public totalLiqShares;
  uint256 public liqFees;
  mapping(address => uint256) public liqTokens;
  mapping(address => uint256) public liqEquity;
  mapping(address => uint256) public userShares;


  uint256 public latestRoundId;                     //Last round that we updated price
  mapping(address => uint256) public price;
  mapping(address => uint256) public equity;
  mapping(address => uint256) public supply;

  constructor() public {
    price[bull] = 10**16;
    price[bear] = 10**16;
    supply[bull] = 1000 * 10**18;
    supply[bear] = 1000 * 10**18;

    equity[bull] = price[bull] * supply[bull] / 10**18;
    equity[bear] = price[bear] * supply[bear] / 10**18;
  }

  //TEST data
  uint256[] public testPriceData;
  uint256 public nextroundid;

  function loadNextPrice(uint256[] memory priceData, uint256 roundId) public {
    testPriceData = priceData;
    nextroundid = roundId;
  }

  function tokenBuy(address token, address account) public payable {
    require(msg.value >= minBuy);
    require(token == bull || token == bear);
    updatePrice();


    uint256 fees = msg.value.mul(buyFee).div(10**9);
    uint256 buyeth = msg.value - fees;
    uint256 bonus = getBonus(token, buyeth);
    uint256 tokensToMint = buyeth.add(bonus).mul(10**18).div(price[token]);

    equity[token] = equity[token].add(buyeth).add(bonus);
    if(bonus != 0) balanceEquity -= bonus;
    payFees(fees);
    supply[token] += tokensToMint;
    emit TokenBuy(account, token, tokensToMint, msg.value, fees, bonus);
  }

  function tokenSell(address token, address payable account, uint256 amount) public {
    require(token == bull || token == bear);
    updatePrice();


    uint256 tokensToBurn = amount;
    uint256 selleth = tokensToBurn.mul(price[token]).div(10**18);
    uint256 penalty = getPenalty(token, selleth);
    uint256 fees = sellFee.mul(selleth.sub(penalty)).div(10**9);
    uint256 ethout = selleth.sub(penalty).sub(fees);

    equity[token] = equity[token].sub(ethout);
    if(penalty != 0) balanceEquity += penalty;
    payFees(fees);
    supply[token] -= tokensToBurn;
    account.transfer(ethout);
    emit TokenSell(account, token, tokensToBurn, ethout, fees, penalty);
  }




  function updatePrice() public returns(bool) {
    uint256[] memory priceData;
    uint256 roundId;
    (priceData, roundId) = (testPriceData, nextroundid);
    if(priceData.length >= 2) {
      _updatePrice(priceData, roundId);
      return(true);
    }
    else {
      return(false);
    }
  }

  function _updatePrice(uint256[] memory priceData, uint256 roundId) public {
    uint256 bullEquity = getTokenEquity(bull);
    uint256 bearEquity = getTokenEquity(bear);
    uint256 totalEquity = getTotalEquity();
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
          pricedelta = priceData[i-1].sub(priceData[i]);
          pricedelta = pricedelta.mul(10**9).div(priceData[i-1]);
          pricedelta = pricedelta.mul(multiplier.mul(bullKFactor)).div(10**9);
          pricedelta = pricedelta < lossLimit ? pricedelta : lossLimit;
          movement = bullEquity.mul(pricedelta).div(10**9);
          bearEquity = bearEquity.add(movement);
          bullEquity = totalEquity.sub(bearEquity);
        }
        //BULLISH MOVEMENT
        else if(priceData[i-1] < priceData[i]) {
          pricedelta = priceData[i].sub(priceData[i-1]);
          pricedelta = pricedelta.mul(10**9).div(priceData[i-1]);
          pricedelta = pricedelta.mul(multiplier.mul(bearKFactor)).div(10**9);
          pricedelta = pricedelta < lossLimit ? pricedelta : lossLimit;
          movement = bearEquity.mul(pricedelta).div(10**9);
          bullEquity = bullEquity.add(movement);
          bearEquity = totalEquity.sub(bullEquity);
        }
      }
    }
    if(bullEquity != getTokenEquity(bull) || bearEquity != getTokenEquity(bear)) {

      price[bull] = bullEquity.mul(10**18).div(supply[bull].add(liqTokens[bull]));
      price[bear] = bearEquity.mul(10**18).div(supply[bear].add(liqTokens[bear]));

      liqEquity[bull] = price[bull].mul(liqTokens[bull]).div(10**18);
      liqEquity[bear] = price[bear].mul(liqTokens[bear]).div(10**18);

      equity[bull] = bullEquity.sub(liqEquity[bull]);
      equity[bear] = bearEquity.sub(liqEquity[bear]);

    }

    latestRoundId = roundId;

    emit PriceUpdate(latestRoundId, price[bull], price[bear]);
  }

  function payFees(uint256 amount) internal {
    feeRecipientProxy.transfer(amount.div(2));
    liqFees += amount.sub(amount.div(2));
  }

  function getKFactor(uint256 tokenEquity, uint256 bullEquity, uint256 bearEquity, uint256 totalEquity)
  public
  view
  returns(uint256) {
    if(bullEquity  == 0 || bearEquity == 0) {
      return(0);
    }
    else {
      tokenEquity = tokenEquity > 0 ? tokenEquity : 1;
      uint256 kFactor = totalEquity.mul(10**9).div(tokenEquity.mul(2)) < kControl ? totalEquity.mul(10**9).div(tokenEquity.mul(2)): kControl;
      return(kFactor);
    }
  }

  function getBonus(address token, uint256 eth) public view returns(uint256) {
    uint256 totaleth0 = getTotalEquity();
    uint256 totaleth1 = totaleth0.add(eth);
    uint256 tokeneth0 = getTokenEquity(token);
    uint256 tokeneth1 = tokeneth0.add(eth);
    uint256 kFactor = getKFactor(tokeneth0, getTokenEquity(bull), getTokenEquity(bear), totaleth0);
    bool t = kFactor == 0 ? tokeneth0 == 0 : true;
    if(t == true && balanceEquity > 0 && totaleth0 > tokeneth0 * 2) {
      uint256 ratio0 = tokeneth0.mul(10**18).div(totaleth0);
      uint256 ratio1 = tokeneth1.mul(10**18).div(totaleth1);
      uint256 bonus = ratio1 <= 5 * 10**17 ? ratio1.sub(ratio0).mul(10**18).div(5 * 10**17 - ratio0).mul(balanceEquity).div(10**18) : balanceEquity;
      return(bonus);
    }
    else {
      return(0);
    }
  }

  function getPenalty(address token, uint256 eth) public view returns(uint256) {
    uint256 totaleth0 = getTotalEquity();
    uint256 totaleth1 = totaleth0.sub(eth);
    uint256 tokeneth0 = getTokenEquity(token);
    uint256 tokeneth1 = tokeneth0.sub(eth);
    if(totaleth0.div(2) >= tokeneth1) {
      uint256 ratio0 = tokeneth0.mul(10**18).div(totaleth0);
      uint256 ratio1 = tokeneth1.mul(10**18).div(totaleth1);
      uint256 penalty = ratio0.sub(ratio1).div(2);
      penalty = balanceControlFactor.mul(penalty).div(10**9);
      return(penalty);
    }
    else {
      return(0);
    }
  }

  function getSharePrice() public view returns(uint256) {
    if(totalLiqShares == 0) {
      return(liqEquity[bull].add(liqEquity[bear]).add(liqFees).add(10**18));
    }
    else {
      return(liqEquity[bull].add(liqEquity[bear]).add(liqFees).mul(10**18).div(totalLiqShares));
    }
  }

  function getLiqAddTokens(uint256 eth)
    public
    view
    returns(
      uint256 rbullEquity,
      uint256 rbearEquity,
      uint256 rbullToknes,
      uint256 rbearTokens
    ) {
    uint256 bullEquity = liqEquity[bull] < liqEquity[bear] ? liqEquity[bear].sub(liqEquity[bull]) : 0 ;
    uint256 bearEquity = liqEquity[bear] < liqEquity[bull] ? liqEquity[bull].sub(liqEquity[bear]) : 0 ;

    if(bullEquity >= eth) bullEquity = eth;
    else if(bearEquity >= eth) bearEquity = eth;
    else if(bullEquity > bearEquity) {
      bullEquity = bullEquity.add(eth.sub(bullEquity).div(2));
      bearEquity = eth.sub(bullEquity);
    }
    else if(bearEquity > bullEquity) {
      bearEquity = bearEquity.add(eth.sub(bearEquity).div(2));
      bullEquity = eth.sub(bearEquity);
    }
    else {
      bullEquity = eth.div(2);
      bearEquity = eth.sub(bullEquity);
    }
    return(
      bullEquity,
      bearEquity,
      bullEquity.mul(10**18).div(price[bull]),
      bearEquity.mul(10**18).div(price[bear])
    );
  }
  function getLiqRemoveTokens(uint256 eth)
    public
    view
    returns(
      uint256 rbullEquity,
      uint256 rbearEquity,
      uint256 rbullToknes,
      uint256 rbearTokens
    ) {
    uint256 bullEquity = liqEquity[bull] > liqEquity[bear] ? liqEquity[bull].sub(liqEquity[bear]) : 0 ;
    uint256 bearEquity = liqEquity[bear] > liqEquity[bull] ? liqEquity[bear].sub(liqEquity[bull]) : 0 ;

    if(bullEquity >= eth) bullEquity = eth;
    else if(bearEquity >= eth) bearEquity = eth;
    else if(bullEquity > bearEquity) {
      bullEquity = bullEquity.add(eth.sub(bullEquity).div(2));
      bearEquity = eth.sub(bullEquity);
    }
    else if(bearEquity > bullEquity) {
      bearEquity = bearEquity.add(eth.sub(bearEquity).div(2));
      bullEquity = eth.sub(bearEquity);
    }
    else {
      bullEquity = eth.div(2);
      bearEquity = eth.sub(bullEquity);
    }
    uint256 bullTokens = bullEquity.mul(10**18).div(price[bull]);
    uint256 bearTokens = bearEquity.mul(10**18).div(price[bear]);
    bullTokens = bullTokens > liqTokens[bull] ? liqTokens[bull] : bullTokens;
    bearTokens = bearTokens > liqTokens[bear] ? liqTokens[bear] : bearTokens;
      return(
        bullEquity,
        bearEquity,
        bullTokens,
        bearTokens
      );
  }


  function getLatestRoundId() public view returns(uint256) {
    return(latestRoundId);
  }

  function getTotalEquity() public view returns(uint256) {
    return(getTokenEquity(bear).add(getTokenEquity(bull)));
  }

  function getTokenEquity(address _token) public view returns(uint256) {
    return(equity[_token].add(liqEquity[_token]));
  }
  function getTokenLiqEquity(address token) public view returns(uint256) {
    return(liqTokens[token].mul(price[token]).div(10**18));
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
