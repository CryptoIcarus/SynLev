//////////////////////////////////////////////////
//SYNLEV VAULT CONTRACT V 0.1.0
//////////////////////////

pragma solidity >= 0.6.6;

import './ownable.sol';
import './SafeMath.sol';
import './SignedSafeMath.sol';
import './IERC20.sol';

interface vaultPriceAggregatorInterface {
  function priceRequest(address vault, uint256 lastUpdated) external view returns(int256[] memory, uint256);
}
interface priceAggregator {
  function registerVaultAggregator(address aggregator) external;
}


contract vault is Owned {
  using SafeMath for uint256;
  using SignedSafeMath for int256;
  constructor() public {
    //REGISTERS SELF ON PRICE AGGREGATOR PROXY
    //1ST ADDRESS IS NON PROXIED PRICE AGGREGATOR
    //2ND ADDRESS IS CHAINLINK PRICE ORACLE
    priceAggregator(0x74faB436e67e322E576fB9d37e653805F41a7E18).registerVaultAggregator(0x9326BFA02ADD2366b30bacB125260Af641031331);
    //SET ADJUSTABLE VARIABLES
    lossLimit = 9 * 10**8;
    kControl = 15 * 10**8;
    balanceControlFactor = 10**9;
    buyFee = 4 * 10**6;
    sellFee = 4 * 10**6;
    //GRABS LATEST ROUND ON CONSTRUCTION, DOES NOTHING WITH PRICE DATA
    ( , latestRoundId) = priceProxy.priceRequest(address(this), latestRoundId);
    //TURN ON ON CONSTRUCTION
    //TODO REMOVE ON PRODUCTION
    active = true;
  }
  /////////////////////
  //EVENTS/////////////
  /////////////////////
  event PriceUpdate(
    uint256 bullPrice,
    uint256 bearPrice,
    uint256 bullLiqEquity,
    uint256 bearLiqEquity,
    uint256 bullEquity,
    uint256 bearEquity,
    uint256 roundId
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

  modifier isActive() {
    require(active == true);
    _;
  }
  /////////////////////
  //GLOBAL VARIBLES
  /////////////////////

  //ACTIVE FLAG
  bool public active;

  //LAST ROUND WE UPDATED PRICEDATA
  uint256 public latestRoundId;

  //BULL & BEAR TOKENS CONTRACTS
  //ONLY SET ONCE BY SETTOKENS()
  //TODO MIGRATE TO USING UP AND DOWN INSTEAD OF BULL AND BEAR
  address public bull;
  address public bear;

  //IMMUTABLE PRICE PROXY CONTRACT
  vaultPriceAggregatorInterface constant public priceProxy = vaultPriceAggregatorInterface(0xE115662B3eD0D9db3af0b09C5859e405B36D1622);
  //IMMUTABLE FEE RECIPIENT PROXY
  address payable constant public feeRecipientProxy = 0xb6C069e09dC272199280D3d25480241325d3F2dd;

  //LEVERAGE AND PRICE CONTROL VARIABLES
  //ONLY MULTIPLIER IS IMMUTABLE
  uint256 constant public multiplier = 3;
  uint256 public lossLimit;
  uint256 public kControl;
  uint256 public balanceEquity;
  uint256 public balanceControlFactor;

  //FEE VARIABLES
  //BUYFEE IS NOT RESTRICTED SET BY SETBUYFEE()
  //SELLFEE RESTRICTED TO 1% MAXIMUM SET BY SETSELLFEE()
  //FEES IS A PRECENTAGE SCALED 10^9
  uint256 public buyFee;
  uint256 public sellFee;

  //LIUIDITY DATA
  //TODO POSSIBLY TOKENIZE LP SHARES
  uint256 public totalLiqShares;
  uint256 public liqFees;
  mapping(address => uint256) public liqTokens;
  mapping(address => uint256) public liqEquity;
  mapping(address => uint256) public userShares;

  //BULL/BEAR PRICES AND EQUITY
  //MAPPED TO ERC20 CONTRACT ADDRESS --> ETH
  mapping(address => uint256) public price;
  mapping(address => uint256) public equity;

  //FALLBACK FUNCTION
  receive() external payable {}

  ////////////////////////////////////
  //LOW LEVEL BUY AND SELL FUNCTIONS//
  //        NO SAFETY CHECK         //
  //SHOULD ONLY BE CALLED BY OTHER  //
  //          CONTRACTS             //
  ////////////////////////////////////

  //BUY BULL OR BEAR TOKENS
  //IS NOT PAYABLE AS TO BE EASILY CALLED BY PROXY CONTRACT,
  //LOOKS HOW MUCH EXCESS ETH CONTRACT HAS
  function tokenBuy(address token, address account) public virtual  {
    //HOW MUCH EXCESS ETH DO WE HAVE?
    uint256 ethin = getDepositEquity();
    //DON'T ALLOW 0 ETH TOKEN BUY AND MUST BE A REAL TOKEN
    require(ethin > 0);
    require(token == bull || token == bear);
    //UPDATE PRICE BEFORE ANY CALCULATION DONE
    updatePrice();
    //CREATE IERC20 TOKEN INTERFACE
    IERC20 itkn = IERC20(token);
    //CALC FEES
    uint256 fees = ethin.mul(buyFee).div(10**9);
    //ETH LESS FEES
    uint256 buyeth = ethin.sub(fees);
    //GRAB BONUS IN ETH
    uint256 bonus = getBonus(token, buyeth);
    //CALC TOKENS TO MINT RESULTS IN ERROR ON IF PRICE REACHES 0
    uint256 tokensToMint = buyeth.add(bonus).mul(10**18).div(price[token]);
    //UPDATE TOKEN EQUITY
    equity[token] = equity[token].add(buyeth).add(bonus);
    //IF BONUS WAS APPLIED UPDATE THE BALANCE EQUITY
    if(bonus != 0) balanceEquity = balanceEquity.sub(bonus);
    //PAY THE LP AND SYN STAKERS
    payFees(fees);
    //MINT TOKENS TO ACCOUNT
    itkn.mint(account, tokensToMint);
    emit TokenBuy(account, token, tokensToMint, ethin, fees, bonus);
  }

  //SELL BULL OR BEAR TOKENS
  //LOOKS HOW MANY TOKENS CONTRACT IS HOLDING,
  function tokenSell(address token, address payable account) public virtual {
    //CREATE IERC20 TOKEN INTERFACE
    IERC20 itkn = IERC20(token);
    //HOW MANY TOKENS DOES
    uint256 tokensToBurn = itkn.balanceOf(address(this));
    //DONT ALLOW 0 TOKEN SELL AND MUST BE A REAL TOKEN
    require(tokensToBurn > 0);
    require(token == bull || token == bear);
    //UPDATE PRICE BEFORE ANY CALCULATION DONE
    updatePrice();
    //CALCUALTE RESULTING ETH FROM TOKENS SOLD BURNED
    uint256 selleth = tokensToBurn.mul(price[token]).div(10**18);
    //GRAB PENALTY IN ETH
    uint256 penalty = getPenalty(token, selleth);
    //CALC FEES IN ETH
    uint256 fees = sellFee.mul(selleth.sub(penalty)).div(10**9);
    //RESULTING ETH LESS PENALTY AND FEES
    uint256 ethout = selleth.sub(penalty).sub(fees);
    //UPDATE TOKEN EQUITY
    equity[token] = equity[token].sub(selleth);
    //IF PENALTY UPDATE BALANCE EQUITY
    if(penalty != 0) balanceEquity = balanceEquity.add(penalty);
    //PAY THE LP AND SYN STAKERS
    payFees(fees);
    //BURN THEM TOKENS
    itkn.burn(tokensToBurn);
    //SEND SELLER THEIR ETH
    account.transfer(ethout);
    emit TokenSell(account, token, tokensToBurn, ethout, fees, penalty);
  }

  //USER ADDING LIQUIDTY DIRECTLY TO VAULT CONTRACT (NO PROXY)
  //LOOKS AT EXCESS ETH SAME AS BUY FUNCTION
  //ONLY DEALS IN TERMS OF TOKEN EQUITY AND SUPPLY. IGNORES PRICES
  //AS LEADS TO ROUNDING ERRORS ERRORS
  function addLiquidity(address account) public payable virtual {
    //HOW MUCH EXCESS ETH DO WE HAVE?
    uint256 ethin = getDepositEquity();
    //DON'T ALLOW ZERO ETH LP
    require(ethin >= 0);
    //UPDATE PRICE BEFORE ANYTHING IS DONE
    updatePrice();
    //CALC RESULTING ADDITIONAL LIQUDITY EQUITY AND TOKEN SUPPLY
    (uint256 bullEquity, uint256 bearEquity, uint256 bullTokens, uint256 bearTokens)
    = getLiqAddTokens(ethin);
    //GRAB LP SHARE PRICE
    uint256 sharePrice = getSharePrice();
    //CALC RESULTING SHARES FROM DEPOSITED ETH
    uint256 resultingShares = ethin.mul(10**18).div(sharePrice);
    //UPDATE ALL LIQUDITY DATA & GIVE USER SHARES
    liqEquity[bull] = liqEquity[bull].add(bullEquity);
    liqEquity[bear] = liqEquity[bear].add(bearEquity);
    liqTokens[bull] = liqTokens[bull].add(bullTokens);
    liqTokens[bear] = liqTokens[bear].add(bearTokens);
    userShares[account] = userShares[account].add(resultingShares);
    totalLiqShares = totalLiqShares.add(resultingShares);

    emit LiquidityAdd(account, ethin, resultingShares, sharePrice);
  }

  //USER DIRECTLY REMOVING LIQUIDY FROM THE VAULT (NO PROXY)
  //TODO IF LIQUDITY IS TOKENIZED THIS CAN BE PROXIED
  function removeLiquidity(uint256 shares) public virtual {
    //USER MUST HAVE SHARES
    require(shares <= userShares[msg.sender]);
    //UPDATE PRICE
    updatePrice();
    //CALC LIQUDITY EQUITY AND TOKEN SUPPLY TO BE REMOVED
    (uint256 bullEquity, uint256 bearEquity, uint256 bullTokens, uint256 bearTokens, uint256 feesPaid)
    = getLiqRemoveTokens(shares);
    //GRAB LP SHARE PRICE
    uint256 sharePrice = getSharePrice();
    //CALC RESULTING ETH FROM BURNED LP SHARES
    uint256 resultingEth = bullEquity.add(bearEquity).add(feesPaid);
    //UPDATE ALL LIQUDITY DATA & BURN USER SHARES
    liqEquity[bull] = liqEquity[bull].sub(bullEquity);
    liqEquity[bear] = liqEquity[bear].sub(bearEquity);
    liqTokens[bull] = liqTokens[bull].sub(bullTokens);
    liqTokens[bear] = liqTokens[bear].sub(bearTokens);
    userShares[msg.sender] = userShares[msg.sender].sub(shares);
    totalLiqShares = totalLiqShares.sub(shares);
    liqFees = liqFees.sub(feesPaid);
    //SEND ETH
    msg.sender.transfer(resultingEth);

    emit LiquidityRemove(msg.sender, resultingEth, shares, sharePrice);
  }

  //PUBLIC UPDATE PRICE FUNCTION
  //RETURNS ALL BOOL IF THE PRICE WAS UPDATED
  //TODO SWITCH TO ALWAYS EMIT PRICE DATA
  function updatePrice(
  )
  public
  returns(bool)
  {
    (
      uint256 bullPrice,
      uint256 bearPrice,
      uint256 bullLiqEquity,
      uint256 bearLiqEquity,
      uint256 bullEquity,
      uint256 bearEquity,
      uint256 roundId
    ) = getUpdatedPrice();
    //ONLY SET IF CHAINLINK ORACLE HAS NEWER ROUNDID
    if(roundId > latestRoundId) {
      (
        price[bull],
        price[bear],
        liqEquity[bull],
        liqEquity[bear],
        equity[bull],
        equity[bear],
        latestRoundId
      ) =
      (
        bullPrice,
        bearPrice,
        bullLiqEquity,
        bearLiqEquity,
        bullEquity,
        bearEquity,
        roundId
      );
      emit PriceUpdate(
        price[bull],
        price[bear],
        liqEquity[bull],
        liqEquity[bear],
        equity[bull],
        equity[bear],
        latestRoundId
      );
      return(true);
    }
    else {
      return(false);
    }
  }

  ///////////////////////
  //INTERNAL FUNCTIONS///
  ///////////////////////

  //SPLITS ANY FEES IF BETWEEN SYN STAKERS AND LP
  //TODO HANDLE CASE THAT THERE ARE NO LP
  function payFees(uint256 amount) internal {
    feeRecipientProxy.transfer(amount.div(2));
    liqFees += amount.sub(amount.div(2));
  }

  ///////////////////
  ///VIEW FUNCTIONS//
  ///////////////////

  //CALCUALTES UPDATED PRICE DATA
  //IF THERE IS NO NEW PRICE DATA JUST RETURNS CURRENT PRICE DATA
  //SAFETY CHECKS ARE DONE BY PRICE AGGREGATOR CONTRACT
  //NAME IS MISLEADING, DOES NOT PRICE CALCUALTIONS. CALCUALTES PRICES BASED
  //ON EQUITY.
  //IMPORTANT TO CALCULATE THE PRICE FROM UP/DOWN PERSPECTIVE AS ROUNDING
  //INACCURACY OVER TIME WILL ADD UP IF CALCUALTIONS ARE ALWAYS DONE FROM THE
  //SAME PERSPECTIVE 
  function getUpdatedPrice()
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
    //REQUESTS PRICE DATA FROM PRICE AGGREGATOR PROXY
    (
      int256[] memory priceData,
      uint256 roundId
    ) = priceProxy.priceRequest(address(this), latestRoundId);
    //ONLY UPDATE IF PRICE DATA IF PRICE ARRAY CONTAINS 2 OR MORE VALUES
    //IF THERE IS NO NEW PRICE DATA PRICEDATE ARRAY WILL HAVE 0 LENGTH
    if(priceData.length > 0) {
      //TODO MIGRATE BELOW DECLARED VARIABLES TO LIVE AFTER TOKEN EQUITY CHECK
      //FOR POTENTIAL GAS SAVINGS
      //GRAB CURRENT TOKEN EQUITY DATA
      uint256 bullEquity = getTokenEquity(bull);
      uint256 bearEquity = getTokenEquity(bear);
      uint256 totalEquity = getTotalEquity();
      //DECLARE VARIALBES FOR KEEPING TRACK OF PRICE DURRING CALCUALTIONS
      uint256 movement;
      uint256 bearKFactor;
      uint256 bullKFactor;
      uint256 pricedelta;
      //ONLY UPDATE IF THERE IS SOME BULL/BEAR EQUITY
      if(bullEquity != 0 && bearEquity != 0) {
        //PRICE CALC LOOP
        for (uint i = 1; i < priceData.length; i++) {
          //GRAB K FACTOR BASED ON RUNNING EQUITY
          //TODO CHECK IF MORE GAS EFFIECNT TO CREATE TWO SEPARATE FUNCTIONS
          //FOR TOKEN K VALUES
          bullKFactor = getKFactor(bullEquity, bullEquity, bearEquity, totalEquity);
          bearKFactor = getKFactor(bearEquity, bullEquity, bearEquity, totalEquity);
          if(priceData[i-1] != priceData[i]) {
            //BEARISH MOVEMENT, CALC EQUITY FROM THE PERSPECTIVE OF BULL
            if(priceData[i-1] > priceData[i]) {
              //TREATS 0 PRICE VALUE AS 1, 0 CAUSES DIVIDES BY 0 ERROR
              if(priceData[i-1] == 0) priceData[i-1] = 1;
              //GETS PRICE CHANGE IN ABSOLUTE TERMS.
              //HANDLES POSSIBLE NEGATIVE PRICE DATA
              pricedelta = priceData[i-1] > 0 ?
                uint256(priceData[i-1].sub(priceData[i]).mul(10**9).div(priceData[i-1])) :
                uint256(-priceData[i-1].sub(priceData[i]).mul(10**9).div(priceData[i-1]));
              //CONVERTS PRICE CHANGE TO BE IN TERMS OF BULL EQUITY CHANGE
              //AS A PERCENTAGE
              pricedelta = pricedelta.mul(multiplier.mul(bullKFactor)).div(10**9);
              //DONT ALLOW LOSS TO BE GREATER THAN SET LOSS LIMIT
              pricedelta = pricedelta < lossLimit ? pricedelta : lossLimit;
              //CALCULATE EQUITY LOSS OF BULL EQUITY
              movement = bullEquity.mul(pricedelta).div(10**9);
              //ADDS EQUITY MOVEMENT TO RUNNING BEAR EUQITY AND REMOVES THAT
              //LOSS FROM RUNNING BULL EQUITY
              bearEquity = bearEquity.add(movement);
              bullEquity = totalEquity.sub(bearEquity);
            }
            //BULLISH MOVEMENT, CALC EQUITY FROM THE PERSPECTIVE OF BEAR
            //SAME PROCESS AS ABOVE. ONLY FROM BEAR PERSPECTIVE
            else if(priceData[i-1] < priceData[i]) {
              if(priceData[i] == 0) priceData[i] = 1;
              pricedelta = priceData[i] > 0 ?
                uint256(priceData[i].sub(priceData[i-1]).mul(10**9).div(priceData[i-1])) :
                uint256(-priceData[i].sub(priceData[i-1]).mul(10**9).div(priceData[i-1]));
              pricedelta = pricedelta.mul(multiplier.mul(bearKFactor)).div(10**9);
              pricedelta = pricedelta < lossLimit ? pricedelta : lossLimit;
              movement = bearEquity.mul(pricedelta).div(10**9);
              bullEquity = bullEquity.add(movement);
              bearEquity = totalEquity.sub(bullEquity);
            }
          }
        }
        return(
          bullEquity.mul(10**18).div(IERC20(bull).totalSupply().add(liqTokens[bull])),
          bearEquity.mul(10**18).div(IERC20(bear).totalSupply().add(liqTokens[bear])),
          price[bull].mul(liqTokens[bull]).div(10**18),
          price[bear].mul(liqTokens[bear]).div(10**18),
          bullEquity.sub(liqEquity[bull]),
          bearEquity.sub(liqEquity[bear]),
          roundId
        );
      }
    }
    else {
      return(
        price[bull],
        price[bear],
        liqEquity[bull],
        liqEquity[bear],
        equity[bull],
        equity[bear],
        roundId
      );
    }
  }

  //K FACTOR OF 1 (10^9) REPRESENTS A 1:1 RATIO OF BULL : BEAR EQUITY
  function getKFactor(uint256 targetEquity, uint256 bullEquity, uint256 bearEquity, uint256 totalEquity)
  public
  view
  returns(uint256) {
    if(bullEquity  == 0 || bearEquity == 0) {
      return(0);
    }
    else {
      uint256 tokenEquity = targetEquity;
      tokenEquity = tokenEquity > 0 ? tokenEquity : 1;
      uint256 kFactor = totalEquity.mul(10**9).div(tokenEquity.mul(2)) < kControl ? totalEquity.mul(10**9).div(tokenEquity.mul(2)): kControl;
      return(kFactor);
    }
  }

  function getBonus(address token, uint256 eth) public view returns(uint256) {
    uint256 totaleth0 = getTotalEquity();
    uint256 tokeneth0 = getTokenEquity(token);
    uint256 kFactor = getKFactor(tokeneth0, getTokenEquity(bull), getTokenEquity(bear), totaleth0);
    bool t = kFactor == 0 ? tokeneth0 == 0 : true;
    if(t == true && balanceEquity > 0 && totaleth0 > tokeneth0 * 2) {
      uint256 ratio0 = tokeneth0.mul(10**18).div(totaleth0);
      uint256 ratio1 = tokeneth0.add(eth).mul(10**18).div(totaleth0.add(eth));
      return(ratio1 <= 5 * 10**17 ? ratio1.sub(ratio0).mul(10**18).div(5 * 10**17 - ratio0).mul(balanceEquity).div(10**18) : balanceEquity);
    }
    else {
      return(0);
    }
  }

  function getPenalty(address token, uint256 eth) public view returns(uint256) {
    uint256 totaleth0 = getTotalEquity();
    uint256 tokeneth0 = getTokenEquity(token);
    uint256 tokeneth1 = tokeneth0.sub(eth);
    if(totaleth0.div(2) >= tokeneth1) {
      uint256 ratio0 = tokeneth0.mul(10**18).div(totaleth0);
      uint256 ratio1 = tokeneth1.mul(10**18).div(totaleth0.sub(eth));
      return(balanceControlFactor.mul(ratio0.sub(ratio1).div(2)).mul(eth).div(10**9).div(10**18));
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
    uint256 rbullTokens,
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
  function getLiqRemoveTokens(uint256 shares)
  public
  view
  returns(
    uint256 rbullEquity,
    uint256 rbearEquity,
    uint256 rbullToknes,
    uint256 rbearTokens,
    uint256 rfeesPaid
  ) {
    uint256 eth = shares.mul(liqEquity[bull].add(liqEquity[bear]).mul(10**18).div(totalLiqShares)).div(10**18);
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
    uint256 feesPaid = liqFees.mul(shares).mul(10**18);
    feesPaid = feesPaid.div(totalLiqShares).div(10**18);
    feesPaid = shares <= totalLiqShares ? feesPaid : liqFees;

    return(
      bullEquity,
      bearEquity,
      bullTokens,
      bearTokens,
      feesPaid
    );
  }

  //FOR OTHER CONTRACTS TO CALL ANY NON CONSTANT VARIABLE OR MAPPING
  function getBullToken() public view returns(address) {return(bull);}
  function getBearToken() public view returns(address) {return(bear);}
  function getMultiplier() public pure returns(uint256) {return(multiplier);}
  function getLossLimit() public view returns(uint256) {return(lossLimit);}
  function getkControl() public view returns(uint256) {return(kControl);}
  function getBalanceEquity() public view returns(uint256) {return(balanceEquity);}
  function getBalanceControlFactor() public view returns(uint256) {return(balanceControlFactor);}
  function getBuyFee() public view returns(uint256) {return(buyFee);}
  function getSellFee() public view returns(uint256) {return(sellFee);}
  function getTotalLiqShares() public view returns(uint256) {return(totalLiqShares);}
  function getLiqFees() public view returns(uint256) {return(liqFees);}
  function getLiqTokens(address token) public view returns(uint256) {return(liqTokens[token]);}
  function getLiqEquity(address token) public view returns(uint256) {return(liqEquity[token]);}
  function getUserShares(address token) public view returns(uint256) {return(userShares[token]);}
  function getLatestRoundId() public view returns(uint256) {return(latestRoundId);}
  function getTokenPrice(address token) public view returns(uint256) {return(price[token]);}
  function getEquity(address token) public view returns(uint256) {return(equity[token]);}

  function getTotalEquity() public view returns(uint256) {
    return(getTokenEquity(bear).add(getTokenEquity(bull)));
  }

  function getTokenEquity(address token) public view returns(uint256) {
    return(equity[token].add(liqEquity[token]));
  }
  function getTokenLiqEquity(address token) public view returns(uint256) {
    return(liqTokens[token].mul(price[token]).div(10**18));
  }
  function getDepositEquity() public view returns(uint256) {
    return(address(this).balance.sub(liqFees.add(balanceEquity).add(getTotalEquity())));
  }



  ///////////////////
  //ADMIN FUNCTIONS//
  ///////////////////
  //ONE TIME USE FUNCTION TO SET TOKEN ADDRESSES. THIS CAN NEVER BE CHANGED ONCE SET.
  //Cannot be included in constructor as vault must be deployed before tokens.
  function setTokens(address bearAddress, address bullAddress) public onlyOwner() {
    require(bear == address(0) || bull == address(0));
    (bull, bear) = (bullAddress, bearAddress);
    //SET INITIAL PRICE TO .01 ETH
    (price[bull], price[bear]) = (10**16, 10**16);
  }
  function setActive(bool state) public onlyOwner() {
    active = state;
  }
  //FEES IN THE FORM OF 1 / 10^8
  function setBuyFee(uint256 amount) public onlyOwner() {
    buyFee = amount;
  }
  //SELL FEES LIMITED TO A MAXIMUM OF 1%
  function setSellFee(uint256 amount) public onlyOwner() {
    require(amount <= 10**7);
    sellFee = amount;
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
