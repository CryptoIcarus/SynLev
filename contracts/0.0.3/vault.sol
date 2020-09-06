//////////////////////////////////////////////////
//SYNLEV VAULT CONTRACT V 0.0.3
//////////////////////////

pragma solidity >= 0.6.4;

interface vaultPriceAggregatorInterface {
  function priceRequest(address vault, uint256 lastUpdated) external view returns(uint256[] memory, uint256);
}
interface synFeesProxyInterface {
  function feesToStaking(uint256 amount) external;
}
interface priceAggregator {
  function registerVaultAggregator(address aggregator) external;
}

interface IERC20 {
  function totalSupply() external view returns (uint256);
  function balanceOf(address account) external view returns (uint256);
  function transfer(address recipient, uint256 amount) external returns (bool);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
  function mint(address account, uint256 amount) external;
  function burn(uint256 amount) external;
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract Context {
  constructor () internal { }
  function _msgSender() internal view virtual returns (address payable) {
    return msg.sender;
  }
  function _msgData() internal view virtual returns (bytes memory) {
    this;
    return msg.data;
  }
}

contract Owned {
  address public owner;
  address public newOwner;

  event OwnershipTransferred(address indexed _from, address indexed _to);

  constructor() public {
    owner = msg.sender;
  }

  modifier onlyOwner {
    require(msg.sender == owner);
    _;
  }

  function transferOwnership(address _newOwner) public onlyOwner {
    newOwner = _newOwner;
  }
  function acceptOwnership() public {
    require(msg.sender == newOwner);
    emit OwnershipTransferred(owner, newOwner);
    owner = newOwner;
    newOwner = address(0);
  }
}


contract vault is Context, Owned {
  using SafeMath for uint256;
  constructor() public {
    priceAggregator(0x91a366C4cA2592B01846abc44B10AE9c08Db7cF9).registerVaultAggregator(0x30B5068156688f818cEa0874B580206dFe081a03);
  }

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

  //token and proxy interfaces
  vaultPriceAggregatorInterface constant public priceProxy = vaultPriceAggregatorInterface(0x975efdF5643cbe4d512302D6CF587777BCbB2f4C);  // Put proxy address here
  address public bull;
  address public bear;

  //Leverage and price control variables
  uint256 constant public multiplier = 3;
  uint256 public lossLimit;
  uint256 public minBuy;
  uint256 public kControl;
  uint256 public balanceEquity;
  uint256 public balanceControlFactor;

  //Fee variables
  //FEES TAKEN AS A PRECENTAGE SCALED 10^8
  uint256 public buyFee;
  uint256 public sellFee;
  address payable constant public feeRecipientProxy = 0xB376d5B864248C3e7587A306e667518356dd0cb2;  //Put proxy address (will chain fallback functions)

  //Liquidity data
  uint256 public totalLiqShares;
  uint256 public liqFees;
  mapping(address => uint256) public liqTokens;
  mapping(address => uint256) public liqEquity;
  mapping(address => uint256) public userShares;


  //Pricing and equity data
  uint256 public latestRoundId;                     //Last round that we updated price
  mapping(address => uint256) public price;
  mapping(address => uint256) public equity;



  ////////////////////////////////////
  //LOW LEVEL BUY AND SELL FUNCTIONS//
  //        NO SAFETY CHECK!!       //
  //SHOULD ONLY BE CALLED BY OTHER  //
  //          CONTRACTS             //
  ////////////////////////////////////
  function tokenBuy(address token, address account) public payable {
    require(msg.value >= minBuy);
    require(token == bull || token == bear);
    updatePrice();

    IERC20 itkn = IERC20(token);
    uint256 fees = msg.value.mul(buyFee).div(10**8);
    uint256 buyeth = msg.value - fees;
    uint256 bonus = getBonus(token, buyeth);
    uint256 tokensToMint = buyeth.add(bonus).mul(10**18).div(price[token]);

    equity[token] = equity[token].add(msg.value).add(bonus);
    payFees(fees);
    itkn.mint(account, tokensToMint);
    emit TokenBuy(account, token, tokensToMint, msg.value, fees, bonus);
  }

  function tokenSell(address token, address payable account) public {
    require(token == bull || token == bear);
    updatePrice();

    IERC20 itkn = IERC20(token);
    uint256 tokensToBurn = itkn.balanceOf(address(this));
    uint256 selleth = tokensToBurn.mul(price[token]).div(10**18);
    uint256 penalty = getPenalty(token, selleth);
    uint256 fees = sellFee.mul(selleth.sub(penalty)).div(10**8);
    uint256 ethout = selleth.sub(penalty).sub(fees);

    equity[token] = equity[token].sub(ethout);
    payFees(fees);
    itkn.burn(tokensToBurn);
    account.transfer(ethout);
    emit TokenSell(account, token, tokensToBurn, selleth, fees, penalty);
  }

  function liquidityAdd(address account) public payable {
    require(msg.value > 0);
    uint256 eth = msg.value;
    uint256 sharePrice = getSharePrice();
    uint256 newShares = eth.mul(10**18).div(sharePrice); //Maybe need to mod to avoid < 0 edge case
    (
      uint256 bullEquity,
      uint256 bearEquity,
      uint256 bullTokens,
      uint256 bearTokens
    ) = getLiqAddTokens(eth);
    if(bullEquity != 0) {
      liqEquity[bull] = liqEquity[bull].add(bullEquity);
      liqTokens[bull] = liqTokens[bull].add(bullTokens);
    }
    if(bearEquity != 0) {
      liqEquity[bear] = liqEquity[bear].add(bearEquity);
      liqTokens[bear] = liqTokens[bear].add(bearTokens);
    }
    userShares[account] = userShares[account].add(newShares);
    emit LiquidityAdd(account, eth, newShares, sharePrice);
  }

  function liquidityRemove(uint256 amount) public {
    require(amount > 0);
    require(userShares[msg.sender] <= amount);
    uint256 sharePrice = getSharePrice();
    uint256 eth = sharePrice.mul(amount).div(10**18);
    (
      uint256 bullEquity,
      uint256 bearEquity,
      uint256 bullTokens,
      uint256 bearTokens
    ) = getLiqRemoveTokens(eth);
    if(bullEquity != 0) {
      liqEquity[bull] = liqEquity[bull].sub(bullEquity);
      liqTokens[bull] = liqTokens[bull].sub(bullTokens);
    }
    if(bearEquity != 0) {
      liqEquity[bear] = liqEquity[bear].sub(bearEquity);
      liqTokens[bear] = liqTokens[bear].sub(bearTokens);
    }
    userShares[msg.sender] = userShares[msg.sender].sub(amount);
    emit LiquidityRemove(msg.sender, eth, amount, sharePrice);
  }



  //PUBLIC PRICE UPDATE RETURNS A BOOL IF NO PRICE UPDATE NEEDED
  function updatePrice() public returns(bool) {
    uint256[] memory priceData;
    uint256 roundId;
    (priceData, roundId) = priceProxy.priceRequest(address(this), latestRoundId);
    if(priceData.length >= 2) {
      _updatePrice(priceData, roundId);
      return(true);
    }
    else {
      return(false);
    }
  }


  //LOW LEVEL PRICE UPDATE
  //TAKES RAW PRICE DATA
  //PUBLIC FUNCTIONS RUN SAFETY CHECKS
  //ORACLE IS RESPONSIBLE OF CHECKING THAT IT DOESN'T SEND TOO MUCH PRICE DATA TO CAUSE GAS OVERFLOW
  function _updatePrice(uint256[] memory priceData, uint256 roundId) internal {
    uint256 bullEquity = getTokenEquity(bull);
    uint256 bearEquity = getTokenEquity(bear);
    uint256 totalEquity = getTotalEquity();
    uint256 movement;

    uint256 bearKFactor;
    uint256 bullKFactor;

    uint256 pricedelta;

    for (uint i = 1; i < priceData.length; i++) {
      bullKFactor = getKFactor(bull, bullEquity, bearEquity, totalEquity);
      bearKFactor = getKFactor(bear, bullEquity, bearEquity, totalEquity);
      //BEARISH MOVEMENT, CALC BULL DATA
      if(priceData[i-1] != priceData[i]) {
        if(priceData[i-1] > priceData[i]) {
          pricedelta = priceData[i-1].mul(10**18).div(priceData[i]).sub(10**18);
          pricedelta = pricedelta.mul(multiplier.mul(bullKFactor)).div(10**18);
          pricedelta = pricedelta < lossLimit ? pricedelta : lossLimit;
          movement = bullEquity.mul(pricedelta).div(10**18);
          bearEquity = bearEquity.add(movement);
          bullEquity = totalEquity.sub(bearEquity);
        }
        //BULLISH MOVEMENT
        else if(priceData[i-1] < priceData[i]) {
          pricedelta = priceData[i].mul(10**18).div(priceData[i-1]).sub(10**18);
          pricedelta = pricedelta.mul(multiplier.mul(bearKFactor)).div(10**18);
          pricedelta = pricedelta < lossLimit ? pricedelta : lossLimit;
          movement = bearEquity.mul(pricedelta).div(10**18);
          bullEquity = bullEquity.add(movement);
          bearEquity = totalEquity.sub(bullEquity);
        }
      }
    }
    if(bullEquity != getTokenEquity(bull) || bearEquity != getTokenEquity(bear)) {
      price[bull] = bullEquity.mul(10**18).div(IERC20(bull).totalSupply().add(liqTokens[bull]));
      price[bear] = bearEquity.mul(10**18).div(IERC20(bear).totalSupply().add(liqTokens[bear]));

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



  ///////////////////
  ///VIEW FUNCTIONS//
  ///////////////////
  //K FACTOR OF 1 (10^9) REPRESENTS A 1:1 RATIO OF BULL : BEAR EQUITY
  function getKFactor(address token, uint256 bullEquity, uint256 bearEquity, uint256 totalEquity)
    public
    view
    returns(uint256) {
    if(bullEquity  == 0 || bearEquity == 0) {
      return(0);
    }
    else {
      uint256 tokenEquity = getTokenEquity(token);
      tokenEquity = tokenEquity > 0 ? tokenEquity : 1;
      uint256 kFactor = totalEquity.mul(10**9).div(tokenEquity.mul(2)) < kControl ? totalEquity.mul(10**9).div(tokenEquity.mul(2)): kControl;
      return(kFactor);
    }
  }

  function getBonus(address token, uint256 eth) public view returns(uint256) {
    uint256 totalEquity = getTotalEquity();
    uint256 tokenEquity = getTokenEquity(token);
    uint256 kFactor = getKFactor(token, getTokenEquity(bull), getTokenEquity(bear), totalEquity);
    bool t = kFactor == 0 ? tokenEquity == 0 : true;
    if(t == true && balanceEquity > 0 && totalEquity > tokenEquity * 2) {
      uint256 bonus = tokenEquity.add(eth).div(totalEquity.sub(tokenEquity)) == 0 ? eth.mul(balanceEquity).mul(10**9).div(totalEquity.div(2).sub(tokenEquity)).div(10**9) : balanceEquity;
      return(bonus);
    }
    else {
      return(0);
    }
  }

  function getPenalty(address token, uint256 eth) public view returns(uint256) {
    uint256 totalEquity = getTotalEquity();
    uint256 reth = getTokenEquity(token).sub(eth);
    if(totalEquity.div(2) >= reth) {
      uint256 penalty = balanceControlFactor.mul(eth.mul(reth.mul(2)));
      penalty = penalty.div(totalEquity.sub(eth)).div(10**9);
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
  //PROBABLY WILL NOT USE
  function getEqualTokens(uint256 eth) public view returns(uint256, uint256) {
    uint256 bulltkns = eth.div(2).mul(price[bull]).div(10**18);
    uint256 beartkns = eth.sub(eth.div(2)).mul(price[bull]).div(10**18);
    return(bulltkns, beartkns);
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

  ///////////////////
  //ADMIN FUNCTIONS//
  ///////////////////
  //ONE TIME USE FUNCTION TO SET TOKEN ADDRESSES. THIS CAN NEVER BE CHANGED ONCE SET.
  //Cannot be included in constructor as vault must be deployed before tokens.
  function setTokens(address bearAddress, address bullAddress, uint256 roundId) public onlyOwner() {
    require(bear == address(0) || bull == address(0));
    (bull, bear) = (bullAddress, bearAddress);
    (price[bull], price[bear]) = ( 10**18, 10**18 );
    latestRoundId = roundId;

  }

  //FEES IN THE FORM OF 1 / 10^8
  function setBuyFee(uint256 amount) public onlyOwner() {
    buyFee = amount;
  }
  //SELL FEES LIMITED TO A MAXIMUM OF 1%
  function setSellFee(uint256 amount) public onlyOwner() {
    require(amount <= 100000);
    sellFee = amount;
  }
  function setMinBuy(uint256 amount) public onlyOwner() {
    minBuy = amount;
  }
  function setLossLimit(uint256 amount) public onlyOwner() {
    lossLimit = amount;
  }
  function setkControl(uint256 amount) public onlyOwner() {
    kControl = amount;
  }

  function setbalanceControlFactor(uint256 amount) public onlyOwner() {
    balanceControlFactor = amount;
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
        uint256 c = a - b;using SafeMath for uint256;

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
