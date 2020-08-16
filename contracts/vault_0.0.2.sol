pragma solidity >= 0.6.4;

interface ioracle {
  function getPriceData() external view returns(uint256[] memory, uint256);
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


contract ETHUSDvault is Owned, Context {
  using SafeMath for uint;

  constructor() public {

    latestRoundId = 9170;



    //TESTING DATA
    bullToken = 0x8468b2bDCE073A157E560AA4D9CcF6dB1DB98507;
    bearToken = 0xB376d5B864248C3e7587A306e667518356dd0cb2;
    equity[bullToken] = 10**18;
    equity[bearToken] = 10**18;

    multiplier = 3;
    lossLimit = 9 * 10**8;
    minBuy = 10**14;
    kControl = 15 * 10**8;
    //balanceControlFactor = ;

    buyFee = 4 * 10**5;
    sellFee = 4 * 10**5;
  }

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


  uint private unlocked = 1;
  modifier lock() {
    require(unlocked == 1, 'DIASEC: LOCKED');
    unlocked = 0;
    _;
    unlocked = 1;
  }

  modifier oracleLock {
    require(oracleLocked == false);
    _;
  }

  ioracle oracle;
  IERC20 public ibullToken;
  IERC20 public ibearToken;

  address public bullToken;
  address public bearToken;

  uint256 latestPriceTimestamp;
  uint256 latestRoundId;
  mapping(address => uint256) public tokenPrice;
  mapping(address => uint256) public equity;

  uint256 public multiplier;
  uint256 public lossLimit;
  uint256 public minBuy;
  uint256 public kControl;
  uint256 public balanceEquity;
  uint256 public balanceControlFactor;

  //FEES TAKEN AS A PRECENTAGE SCALED 10^8
  uint256 public buyFee;
  uint256 public sellFee;
  address payable public feeRecipient;
  bool public tokenSetFlag;
  bool public oracleLocked;

  uint256 public bearEquity;
  uint256 public bullEquity;



  ////////////////////////////////////
  //LOW LEVEL BUY AND SELL FUNCTIONS//
  //        NO SAFETY CHECK!!       //
  //SHOULD ONLY BE CALLED BY OTHER  //
  //          CONTRACTS             //
  ////////////////////////////////////
  function tokenBuy(address _token, address _account) public payable lock() {
    require(msg.value >= minBuy);
    require(_token == bullToken || _token == bearToken);
    _updatePrice();

    IERC20 _itoken = IERC20(_token);

    uint256 _amount = msg.value;
    uint256 _fees = _amount.mul(buyFee).div(10**8);
    uint256 _ethin = _amount - _fees; //ETH FLOWING TO BULL/BEAR EQUITY
    uint256 _bonus = getBonus(_token, _ethin);
    uint256 _tokensToMint = tokenPrice[_token].mul(_ethin.add(_bonus)).div(10**18);

    equity[_token] = equity[_token].add(_ethin).add(_bonus);
    feeRecipient.transfer(_fees);
    _itoken.mint(_account, _tokensToMint);
    emit TokenBuy(_account, _token, _tokensToMint, _amount, _fees, _bonus);
  }

  //VAULT CONTRACT HOLDS ZERO BULL/BEAR TOKENS. THEY (SHOULD) ONYL BE SENT BY A ROUTER CONTRACT.
  //WHEN SELL FUNCTION IS CALLED ALL TOKENS IN VAULT CONTRACT WILL BE BURNED/SOLD FOR ETH
  function tokenSell(address _token, address payable _account) public lock() {
    require(_token == bullToken || _token == bearToken);
    _updatePrice();
    IERC20 _itoken = IERC20(_token);
    uint256 _tokensToBurn = _itoken.balanceOf(address(this));
    uint256 _ethraw = _tokensToBurn.mul(10**18).div(tokenPrice[_token]);
    uint256 _penalty = getPenalty(_token, _ethraw);
    uint256 _fees = sellFee.mul(_ethraw.sub(_penalty)).div(10**8);
    uint256 _ethout = _ethraw.sub(_penalty).sub(_fees);

    bullEquity = bullEquity.sub(_ethraw);
    feeRecipient.transfer(_fees);
    _itoken.burn(_tokensToBurn);
    _account.transfer(_ethout);
    emit TokenSell(_account, _token, _tokensToBurn, _ethraw, _fees, _penalty);
  }



  //ANYONE CAN UPDATE PRICE DATA AT ANY TIME. GIVEN THAT THERE IS A PRICE TO UPDATE
  function publicUpdatePrice() public {
    uint256[] memory _priceData;
    uint256 _roundId;
    (_priceData, _roundId) = oracle.getPriceData();
    require(_priceData.length >= 2);
    updatePrice(_priceData, _roundId);
  }

  //PRIVATE PRICE UPDATE RETURNS A BOOL
  function _updatePrice() private returns(bool) {
    uint256[] memory _priceData;
    uint256 _roundId;
    (_priceData, _roundId) = oracle.getPriceData();
    if(_priceData.length >= 2) {
      updatePrice(_priceData, _roundId);
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
  function updatePrice(uint256[] memory _priceData, uint256 _roundId) public {

    uint256 _bullEquity = equity[bullToken];
    uint256 _bearEquity = equity[bearToken];
    uint256 _totalEquity = getTotalEquity();
    uint256 _movement;

    uint256 _bearKFactor;
    uint256 _bullKFactor;

    uint256 _pricedelta;

    //MOVEMENT CALCULATION LOOP.
    for (uint i = 1; i < _priceData.length; i++) {

      (_bullKFactor, _bearKFactor) = getKFactors();

      //BEARISH MOVEMENT, CALC BULL DATA
      if(_priceData[i-1] != _priceData[i]) {
        if(_priceData[i-1] > _priceData[i]) {
          _pricedelta = _priceData[i-1].mul(10**9).div(_priceData[i]).sub(10**9);
          _pricedelta = _pricedelta.mul(multiplier.mul(_bullKFactor)).div(10**9);
          _pricedelta = _pricedelta < lossLimit ? _pricedelta : lossLimit;
          _movement = _bullEquity.mul(_pricedelta).div(10**9);
          _bearEquity = _bearEquity.add(_movement);
          _bullEquity = _totalEquity.sub(_bearEquity);
        }
        //BULLISH MOVEMENT
        else if(_priceData[i-1] < _priceData[i]) {
          _pricedelta = _priceData[i].mul(10**9).div(_priceData[i-1]).sub(10**9);
          _pricedelta = _pricedelta.mul(multiplier.mul(_bearKFactor)).div(10**9);
          _pricedelta = _pricedelta < lossLimit ? _pricedelta : lossLimit;
          _movement = _bearEquity.mul(_pricedelta).div(10**9);
          _bullEquity = _bullEquity.add(_movement);
          _bearEquity = _totalEquity.sub(_bullEquity);
        }
      }
    }

    if(_bullEquity != bullEquity || _bearEquity != bearEquity) {
      equity[bullToken] = _bullEquity;
      equity[bearToken] = _bearEquity;

      //TESTING ONLY

      tokenPrice[bullToken] = 10**18/_bullEquity;
      tokenPrice[bearToken] = 10**18/_bearEquity;

      //tokenPrice[bullToken] = ibullToken.totalSupply().mul(10**18).div(_bullEquity);
      //tokenPrice[bearToken] = ibearToken.totalSupply().mul(10**18).div(_bearEquity);
    }
    latestRoundId = _roundId;

  }

  ///////////////////
  ///VIEW FUNCTIONS//
  ///////////////////
  //K FACTOR OF 1 (10^9) REPRESENTS A 1:1 RATIO OF BULL : BEAR EQUITY
  function getKFactor(address _token) public view returns(uint256) {
    if(equity[bullToken] == 0 || equity[bearToken] == 0) {
      return(0);
    }
    else {
      uint256 _equity  = equity[_token] > 0 ? equity[_token] : 1;
      uint256 _totalEquity = getTotalEquity();
      uint256 _kFactor = _totalEquity.mul(10**9).div(_equity.mul(2)) < kControl ? _totalEquity.mul(10**9).div(_equity.mul(2)): kControl;
      return(_kFactor);
    }
  }
  function getKFactors() public view returns(uint256, uint256){
    if(equity[bullToken] == 0 || equity[bearToken] == 0) {
      return(0, 0);
    }
    else {
      uint256 _totalEquity = getTotalEquity();
      uint256 _dbullequity  = equity[bullToken] > 0 ? equity[bullToken].mul(2) : 1;
      uint256 _dbearequity  = equity[bearToken] > 0 ? equity[bearToken].mul(2) : 1;
      uint256 _bullKFactor = _totalEquity.mul(10**9).div(_dbullequity) < kControl ? _totalEquity.mul(10**9).div(_dbullequity): kControl;
      uint256 _bearKFactor = _totalEquity.mul(10**9).div(_dbearequity) < kControl ? _totalEquity.mul(10**9).div(_dbearequity): kControl;
      return(_bullKFactor, _bearKFactor);
    }
  }
  function getBonus(address _token, uint256 _ethin) public view returns(uint256){
    uint256 _totalEquity = getTotalEquity();
    uint256 _equity = equity[_token];
    uint256 _kFactor = getKFactor(_token);
    bool _t = _kFactor == 0 ? _equity == 0 : true;
    if(_t == true && balanceEquity > 0 && _totalEquity > _equity*2) {
      uint256 _bonus = _equity.add(_ethin).div(_totalEquity.sub(_equity)) == 0 ? _ethin.mul(balanceEquity).mul(10**9).div(_totalEquity.div(2).sub(_equity).div(10**9) : balanceEquity;
      return(_bonus);
    }
    else {
      return(0);
    }
  }
  function getPenalty(address _token, uint256 _amount) public view returns(uint256){
    uint256 _totalEquity = getTotalEquity();
    uint256 _reth = equity[_token].sub(_amount);
    if(_totalEquity.div(2) < _reth) {
      return(0);
    }
    else {
      uint256 _penalty = balanceControlFactor.mul(_amount.mul(_reth.mul(2)));
      _penalty = _penalty.div(_totalEquity.sub(_amount)).div(10**9);
      return(penalty);
    }
  }

  function getLatestRoundId() public view returns(uint256) {
    return(latestRoundId);
  }
  function getTotalEquity() public view returns(uint256) {
    return(equity[bearToken].add(equity[bullToken]));
  }



  ///////////////////
  //ADMIN FUNCTIONS//
  ///////////////////
  //ONE TIME USE FUNCTION TO SET TOKEN ADDRESSES. THIS CAN NEVER BE CHANGED ONCE SET.
  function setTokens(address _bearToken, address _bullToken) public onlyOwner() {
    require(tokenSetFlag == false);
    bullToken = _bullToken;
    bearToken = _bearToken;
    ibearToken = IERC20(_bearToken);
    ibullToken = IERC20(_bullToken);
    tokenSetFlag = true;
  }
  function setOracle(ioracle _account) public onlyOwner() oracleLock() {
    oracle = _account;
  }
  //TO BE SET WHEN CHAINLINK SETS PERMAMENT PROXY CONTRACTS FOR THEIR PRICE FEEDS.
  function lockOracleForever() public onlyOwner() {
    oracleLocked = true;
  }
  //FEES IN THE FORM OF 1 / 10^8
  function setBuyFee(uint256 _amount) public onlyOwner() {
    buyFee = _amount;
  }
  //SELL FEES LIMITED TO A MAXIMUM OF 1%
  function setSellFee(uint256 _amount) public onlyOwner() {
    require(_amount <= 100000);
    sellFee = _amount;
  }
  function setMinBuy(uint256 _amount) public onlyOwner() {
    minBuy = _amount;
  }
  function setLossLimit(uint256 _amount) public onlyOwner() {
    lossLimit = _amount;
  }
  function setkControl(uint256 _amount) public onlyOwner() {
    kControl = _amount;
  }

  function setbalanceControlFactor(uint256 _amount) public onlyOwner() {
    balanceControlFactor = _amount;
  }

}







library SafeMath {
  /**
  * @dev Returns the addition of two unsigned integers, reverting on
  * overflow.
  *
  * Counterpart to Solidity's `+` operator.
  *
  * Requirements:
  * - Addition cannot overflow.
  */
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    require(c >= a, "SafeMath: addition overflow");

    return c;
  }

  /**
  * @dev Returns the subtraction of two unsigned integers, reverting on
  * overflow (when the result is negative).
  *
  * Counterpart to Solidity's `-` operator.
  *
  * Requirements:
  * - Subtraction cannot overflow.
  */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    return sub(a, b, "SafeMath: subtraction overflow");
  }

  /**
  * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
  * overflow (when the result is negative).
  *
  * Counterpart to Solidity's `-` operator.
  *
  * Requirements:
  * - Subtraction cannot overflow.
  *
  * _Available since v2.4.0._
  */
  function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
    require(b <= a, errorMessage);
    uint256 c = a - b;

    return c;
  }

  /**
  * @dev Returns the multiplication of two unsigned integers, reverting on
  * overflow.
  *
  * Counterpart to Solidity's `*` operator.
  *
  * Requirements:
  * - Multiplication cannot overflow.
  */
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
    // benefit is lost if 'b' is also tested.
    // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
    if (a == 0) {
      return 0;
    }

    uint256 c = a * b;
    require(c / a == b, "SafeMath: multiplication overflow");

    return c;
  }

  /**
  * @dev Returns the integer division of two unsigned integers. Reverts on
  * division by zero. The result is rounded towards zero.
  *
  * Counterpart to Solidity's `/` operator. Note: this function uses a
  * `revert` opcode (which leaves remaining gas untouched) while Solidity
  * uses an invalid opcode to revert (consuming all remaining gas).
  *
  * Requirements:
  * - The divisor cannot be zero.
  */
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    return div(a, b, "SafeMath: division by zero");
  }

  /**
  * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
  * division by zero. The result is rounded towards zero.
  *
  * Counterpart to Solidity's `/` operator. Note: this function uses a
  * `revert` opcode (which leaves remaining gas untouched) while Solidity
  * uses an invalid opcode to revert (consuming all remaining gas).
  *
  * Requirements:
  * - The divisor cannot be zero.
  *
  * _Available since v2.4.0._
  */
  function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
    // Solidity only automatically asserts when dividing by 0
    require(b > 0, errorMessage);
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold

    return c;
  }

  /**
  * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
  * Reverts when dividing by zero.
  *
  * Counterpart to Solidity's `%` operator. This function uses a `revert`
  * opcode (which leaves remaining gas untouched) while Solidity uses an
  * invalid opcode to revert (consuming all remaining gas).
  *
  * Requirements:
  * - The divisor cannot be zero.
  */
  function mod(uint256 a, uint256 b) internal pure returns (uint256) {
    return mod(a, b, "SafeMath: modulo by zero");
  }

  /**
  * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
  * Reverts with custom message when dividing by zero.
  *
  * Counterpart to Solidity's `%` operator. This function uses a `revert`
  * opcode (which leaves remaining gas untouched) while Solidity uses an
  * invalid opcode to revert (consuming all remaining gas).
  *
  * Requirements:
  * - The divisor cannot be zero.
  *
  * _Available since v2.4.0._
  */
  function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
    require(b != 0, errorMessage);
    return a % b;
  }
}
