//////////////////////////////////////////////////
//SYNLEV VAULT CONTRACT V 0.1.0
//////////////////////////

pragma solidity >= 0.6.6;

import './ownable.sol';
import './libraries/SafeMath.sol';
import './libraries/SignedSafeMath.sol';
import './interfaces/IERC20.sol';

interface vaultPriceAggregatorInterface {
  function priceRequest(address vault, uint256 lastUpdated) external view returns(int256[] memory, uint256);
}
interface priceAggregator {
  function registerVaultAggregator(address aggregator) external;
}

/*
 * @title SynLev vault contract that is the heart of the ecosystem. Responsible
 * for calcualting price, holding all price/equity variables, and storing ETH.
 * @author Icarus
 */
contract vault is Owned {
  using SafeMath for uint256;
  using SignedSafeMath for int256;

  /*
   * @notice Contract registers itself on the SynLev price aggregator contract,
   * sets adjustable variables, and grabs latestRoundId
   * @dev First address is non proxied SynLev vault aggregator, second address
   * is chainlink price oracle.
   * TODO remove "active = true" on production
   */
  constructor() public {
    priceAggregator(0x74faB436e67e322E576fB9d37e653805F41a7E18).registerVaultAggregator(0x9326BFA02ADD2366b30bacB125260Af641031331);
    lossLimit = 9 * 10**8;
    kControl = 15 * 10**8;
    balanceControlFactor = 10**9;
    buyFee = 4 * 10**6;
    sellFee = 4 * 10**6;
    ( , latestRoundId) = priceProxy.priceRequest(address(this), latestRoundId);
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

  // A
  bool public active;

  //LAST ROUND WE UPDATED PRICEDATA
  uint256 public latestRoundId;

  /*
   * @notice These are the bull and bear tokens contracts, can only be set
   * once by setTokens()
   */
  address public bull;
  address public bear;

  /*
   * @param vaultPriceAggregatorInterface immutable price aggregator proxy
   * @param feeRecipientProxy immutable fee proxy recipient
   */
  vaultPriceAggregatorInterface constant public priceProxy = vaultPriceAggregatorInterface(0xE115662B3eD0D9db3af0b09C5859e405B36D1622);
  address payable constant public feeRecipientProxy = 0xb6C069e09dC272199280D3d25480241325d3F2dd;

  /*
   * @notice Leverage and price control variables that can be changed by owner
   * to stablize asset pairs, except multiplier
   * @param multiplier The leverage of this asset pair, immutable
   * @param lossLimit The maximum loss on any one price calculation. Scaled
   * 10^9 (9 * 10^8 is a 90% loss)
   * @param kControl Upper bound limit of leverage adjuster. Scaled 10^9
   * (15 * 10^7 represents a maximum leverage level of 4.5X)
   * @param balanceControlFactor Scalar affecting sell penalty. Scaled 10^9
   */
  uint256 constant public multiplier = 3;
  uint256 public lossLimit;
  uint256 public kControl;
  uint256 public balanceEquity;
  uint256 public balanceControlFactor;

  /*
   * @notice Fee variables
   * @param buyFee Buy fee scaled 10^9
   * @param buyFee Sell fee scaled 10^9
   */
  uint256 public buyFee;
  uint256 public sellFee;

  /*
   * @notice Liquidity data variables
   * @param totalLiqShares Total number of LP shares
   * @param liqFees Running total of all fees paid to LP
   * @param liqTokens Virtual bull/bear tokens created by LP
   * @param liqEquity Equity of the Virtual bull/bear tokens
   * @param userShares Ledger of shares owned by LP
   * TODO Possibly tokenize LP shares
   */
  uint256 public totalLiqShares;
  uint256 public liqFees;
  mapping(address => uint256) public liqTokens;
  mapping(address => uint256) public liqEquity;
  mapping(address => uint256) public userShares;

  /*
   * @notice Bull and Bear token prices and equity, not including LP
   * @param price bull/bear token address --> token price
   * @param buyFee bull/bear token address --> token equity
   */
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

  /*
   * @notice Buys bull or bear token and updates price before token buy.
   * @param _token bull or bear token address
   * @param _account Recipient of newly minted tokens
   * @dev Should only be called by a router contract. Checks the excess ETH in
   * contract by calling getDepositEquity(). Can't 0 ETH buy. Calculates
   * resulting tokens and fees. Sends fees and mints tokens.
   *
   */
  function tokenBuy(address _token, address _account) public virtual isActive()  {
    uint256 ethin = getDepositEquity();
    require(ethin > 0);
    require(_token == bull || _token == bear);
    updatePrice();
    IERC20 itkn = IERC20(_token);
    uint256 fees = ethin.mul(buyFee).div(10**9);
    uint256 buyeth = ethin.sub(fees);
    uint256 bonus = getBonus(_token, buyeth);
    uint256 tokensToMint = buyeth.add(bonus).mul(10**18).div(price[_token]);
    equity[_token] = equity[_token].add(buyeth).add(bonus);
    if(bonus != 0) balanceEquity = balanceEquity.sub(bonus);
    payFees(fees);
    itkn.mint(_account, tokensToMint);

    emit TokenBuy(_account, _token, tokensToMint, ethin, fees, bonus);
  }

  /*
   * @notice Sells bull or bear token and updates price before token sell.
   * @param _token bull or bear token address
   * @param _account Recipient of resulting eth from burned tokens
   * @dev Should only be called by a router contract that simultaneously sends
   * tokens using transferFrom() and calls this function. Looks at the current
   * balance of the contract of the selected token. Can't 0 token sell.
   * Calculates resulting ETH from burned tokens. Pays fees, burns tokens, and
   * sends ETH.
   */
  function tokenSell(address token, address payable _account) public virtual {
    IERC20 itkn = IERC20(token);
    uint256 tokensToBurn = itkn.balanceOf(address(this));
    require(tokensToBurn > 0);
    require(token == bull || token == bear);
    updatePrice();
    uint256 selleth = tokensToBurn.mul(price[token]).div(10**18);
    uint256 penalty = getPenalty(token, selleth);
    uint256 fees = sellFee.mul(selleth.sub(penalty)).div(10**9);
    uint256 ethout = selleth.sub(penalty).sub(fees);
    equity[token] = equity[token].sub(selleth);
    if(penalty != 0) balanceEquity = balanceEquity.add(penalty);
    payFees(fees);
    itkn.burn(tokensToBurn);
    _account.transfer(ethout);

    emit TokenSell(_account, token, tokensToBurn, ethout, fees, penalty);
  }

  /*
   * @notice Adds liquidty to the contract and gives LP shares. Minimum LP add
   * is 1 wei. Virtually mints bear/bull tokens to be held in the vault.
   * @param _account Recipient of LP shares
   * @dev Can be called by router but there is benefit to doing so. All
   * calculations are done with respect to equity and supply. Doing by price
   * creates rounding error. Calls updatePrice() then calls getLiqAddTokens()
   * to determine how many bull/bear to create.
   */
  function addLiquidity(address _account) public payable virtual {
    uint256 ethin = getDepositEquity();
    updatePrice();
    (uint256 bullEquity, uint256 bearEquity, uint256 bullTokens, uint256 bearTokens)
    = getLiqAddTokens(ethin);
    uint256 sharePrice = getSharePrice();
    uint256 resultingShares = ethin.mul(10**18).div(sharePrice);
    liqEquity[bull] = liqEquity[bull].add(bullEquity);
    liqEquity[bear] = liqEquity[bear].add(bearEquity);
    liqTokens[bull] = liqTokens[bull].add(bullTokens);
    liqTokens[bear] = liqTokens[bear].add(bearTokens);
    userShares[_account] = userShares[_account].add(resultingShares);
    totalLiqShares = totalLiqShares.add(resultingShares);

    emit LiquidityAdd(_account, ethin, resultingShares, sharePrice);
  }

  /*
   * @notice Removes liquidty to the contract and gives LP shares. Virtually
   * burns bear/bull tokens to be held in the vault. Cannot be called if user
   * has 0 shares
   * @param _shares How many shares to burn
   * @dev Cannot be called by a router as LP shares are not currently tokenized.
   * Calls updatePrice() then calls getLiqRemoveTokens() to determine how many
   * bull/bear tokens to remove.
   * TODO If LP is tokenized check deposit via IERC20 balanceOf()
   */
  function removeLiquidity(uint256 shares) public virtual {
    require(shares <= userShares[msg.sender]);
    updatePrice();
    (uint256 bullEquity, uint256 bearEquity, uint256 bullTokens, uint256 bearTokens, uint256 feesPaid)
    = getLiqRemoveTokens(shares);
    uint256 sharePrice = getSharePrice();
    uint256 resultingEth = bullEquity.add(bearEquity).add(feesPaid);
    liqEquity[bull] = liqEquity[bull].sub(bullEquity);
    liqEquity[bear] = liqEquity[bear].sub(bearEquity);
    liqTokens[bull] = liqTokens[bull].sub(bullTokens);
    liqTokens[bear] = liqTokens[bear].sub(bearTokens);
    userShares[msg.sender] = userShares[msg.sender].sub(shares);
    totalLiqShares = totalLiqShares.sub(shares);
    liqFees = liqFees.sub(feesPaid);
    msg.sender.transfer(resultingEth);

    emit LiquidityRemove(msg.sender, resultingEth, shares, sharePrice);
  }

  /*
   * @notice Updates price from chainlink oracles.
   * @param _shares How many shares to burn
   * @dev Calls getUpdatedPrice() function and sets new price, equity, liquidity
   * equity, and latestRoundId; only if there is new price data
   * @return bool if price was updated
   */
  function updatePrice()
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
      return(true);
    }
    else {
      return(false);
    }
    emit PriceUpdate(
      price[bull],
      price[bear],
      liqEquity[bull],
      liqEquity[bear],
      equity[bull],
      equity[bear],
      latestRoundId
    );
  }

  ///////////////////////
  //INTERNAL FUNCTIONS///
  ///////////////////////

  /*
   * @notice Pays half fees to SYN stakers and half to LP
   * @param _amount Fees to be paid in ETH
   * @dev Only called by tokenBuy() nad tokenSell()
   * TODO Handle case if there are no LP
   */
  function payFees(uint256 amount) internal {
    feeRecipientProxy.transfer(amount.div(2));
    liqFees += amount.sub(amount.div(2));
  }

  ///////////////////
  ///VIEW FUNCTIONS//
  ///////////////////

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
    //Requests price data from price aggregator proxy
    (
      int256[] memory priceData,
      uint256 roundId
    ) = priceProxy.priceRequest(address(this), latestRoundId);
    //Only update if price data if price array contains 2 or more values
    //If there is no new price data pricedate array will have 0 length
    if(priceData.length > 0) {
      //Only update if there is soome bull/bear equity
      uint256 bullEquity = getTokenEquity(bull);
      uint256 bearEquity = getTokenEquity(bear);
      if(bullEquity != 0 && bearEquity != 0) {
        uint256 totalEquity = getTotalEquity();
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
                uint256(priceData[i-1].sub(priceData[i]).mul(10**9).div(priceData[i-1])) :
                uint256(-priceData[i-1].sub(priceData[i]).mul(10**9).div(priceData[i-1]));
              //Converts price change to be in terms of bull equity change
              //As a percentage
              pricedelta = pricedelta.mul(multiplier.mul(bullKFactor)).div(10**9);
              //Dont allow loss to be greater than set loss limit
              pricedelta = pricedelta < lossLimit ? pricedelta : lossLimit;
              //Calculate equity loss of bull equity
              movement = bullEquity.mul(pricedelta).div(10**9);
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

  /*
   * @notice Returns the buy bonus based on the incoming ETH and selected token.
   * Only relevant to token buys
   * @param token The selected bull or bear token
   * @param eth The amount of ETH to be added
   * @return Bonus in ETH
   * TODO Change to simpler check as k factor no longer used to calc bonus
   */
  function getBonus(address token, uint256 eth) public view returns(uint256) {
    //Grab total equity of both tokens
    uint256 totaleth0 = getTotalEquity();
    //Grab total equity of only target token
    uint256 tokeneth0 = getTokenEquity(token);
    //Check if we need to calc a bonus
    if(balanceEquity > 0 && totaleth0 > tokeneth0.mul(2)) {
      //Current ratio of token equity to total equity
      uint256 ratio0 = tokeneth0.mul(10**18).div(totaleth0);
      //Ratio of token equity to total equity after buy
      uint256 ratio1 = tokeneth0.add(eth).mul(10**18).div(totaleth0.add(eth));
      //If the after buy ratio is grater than .5 (50%) we reward the entire
      //balance equity
      return(
        ratio1 <= 5 * 10**17 ?
        ratio1.sub(ratio0).mul(10**18).div(5 * 10**17 - ratio0).mul(balanceEquity).div(10**18) :
        balanceEquity
      );
    }
    else {
      return(0);
    }
  }

  /*
   * @notice Returns the sell penalty based on the outgoing ETH and selected
   * token. Only relevant to token sells.
   * @param token The selected bull or bear token
   * @param eth The amount of outgoing ETH
   * @return Penalty in ETH
   */
  function getPenalty(address token, uint256 eth) public view returns(uint256) {
    //Grab total equity of both tokens
    uint256 totaleth0 = getTotalEquity();
    //Grab total equity of only target token
    uint256 tokeneth0 = getTokenEquity(token);
    //Calc target token equity after sell
    uint256 tokeneth1 = tokeneth0.sub(eth);
    //Only calc penalty if ratio is less than .5 (50%) after token sell
    if(totaleth0.div(2) >= tokeneth1) {
      //Current ratio of token equity to total equity
      uint256 ratio0 = tokeneth0.mul(10**18).div(totaleth0);
      //Ratio of token equity to total equity after buy
      uint256 ratio1 = tokeneth1.mul(10**18).div(totaleth0.sub(eth));
      return(balanceControlFactor.mul(ratio0.sub(ratio1).div(2)).mul(eth).div(10**9).div(10**18));
    }
    else {
      return(0);
    }
  }

  /*
   * @notice Returns the current LP share price. Defaults to 1 ETH if 0 LP
   * @param token The selected bull or bear token
   * @param eth The amount of outgoing ETH
   * @return Penalty in ETH
   */
  function getSharePrice() public view returns(uint256) {
    if(totalLiqShares == 0) {
      return(liqEquity[bull].add(liqEquity[bear]).add(liqFees).add(10**18));
    }
    else {
      return(liqEquity[bull].add(liqEquity[bear]).add(liqFees).mul(10**18).div(totalLiqShares));
    }
  }


  /*
   * @notice Calc how many bull/bear tokens virtually mint based on incoming
   * ETH.
   * @returns bull/bear equity and bull/bear tokens to be added
  */
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

  /*
   * @notice Calc how many bull/bear tokens virtually burn based on shares
   * being removed.
   * @param shares Amount of shares user removing from LP
   * @returns bull/bear equity and bull/bear tokens to be removed
  */
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
