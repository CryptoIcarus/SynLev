pragma solidity >= 0.6.4;

interface vaultPriceAggregatorInterface {
  function priceRequest(address vault, uint256 lastUpdated) external view returns(uint256[] memory, uint256);
}
interface synFeesProxyInterface {
  function feesToStaking(uint256 amount) external view returns();
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

  constructor() public {

  }

  //token and proxy interfaces
  vaultPriceAggregatorInterface constant public priceProxy = vaultPriceAggregatorInterface();  // Put proxy address here
  address public bull;
  IERC20 public ibull;
  address public bear;
  IERC20 public ibear;

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
  synFeesProxyInterface constant public feeRecipientProxy = synFeesProxyInterface();  //Put proxy address (will chain fallback functions)

  //Liquidity data
  uint256 public totalLiqFees;
  uint256 public totalLiqShares;
  mapping(address => uint256) public liqSupply;
  mapping(address => uint256) public liqShares;

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

  }

  function tokenSell(address token, address payable account) public{

  }

  function liquidityAdd() public payable {

  }

  function liquidityRemove(uint256 amount) public {

  }


  //ANYONE CAN UPDATE PRICE DATA AT ANY TIME. GIVEN THAT THERE IS A PRICE TO UPDATE
  function publicUpdatePrice() public {
    int256[] memory priceData;
    uint256 roundId;
    (priceData, roundId) = priceProxy.getPriceData();
    require(priceData.length >= 2);
    updatePrice(priceData, roundId);
  }

  //PRIVATE PRICE UPDATE RETURNS A BOOL
  function _updatePrice() private returns(bool) {
    int256[] memory priceData;
    uint256 roundId;
    (priceData, roundId) = priceProxy.getPriceData();
    if(priceData.length >= 2) {
      updatePrice(priceData, roundId);
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
  function updatePrice(uint256[] memory priceData, uint256 roundId) public {


  }



  ///////////////////
  ///VIEW FUNCTIONS//
  ///////////////////
  //K FACTOR OF 1 (10^9) REPRESENTS A 1:1 RATIO OF BULL : BEAR EQUITY
  function getKFactor(address _token) public view returns(uint256) {

  }

  function getKFactors() public view returns(uint256, uint256) {
    return(getKFactor(bullToken), getKFactor(bearToken));
  }

  function getBonus(address _token, uint256 _ethin) public view returns(uint256) {

  }

  function getPenalty(address _token, uint256 _amount) public view returns(uint256) {

  }

  function getSharePrice() public view returns(uint256) {

  }

  function getLatestRoundId() public view returns(uint256) {

  }

  function getTotalEquity() public view returns(uint256) {

  }

  function getTokenEquity(address _token) public view returns(uint256) {

  }

  ///////////////////
  //ADMIN FUNCTIONS//
  ///////////////////
  //ONE TIME USE FUNCTION TO SET TOKEN ADDRESSES. THIS CAN NEVER BE CHANGED ONCE SET.
  //Cannot be included in constructor as vault must be deployed before tokens.
  function setTokens(address bearAddress, address bullAddress) public onlyOwner() {
    require(bear != address(0) || bull != address(0));
    (
      bull,
      ibull,
      bear,
      ibear
    ) =
    (
      bullAddress,
      IERC20(bullAddress)
      bearAddress,
      IERC20(bearAddress)
    )
  }

  //FEES IN THE FORM OF 1 / 10^8
  function setBuyFee(uint256 amount) public onlyOwner() {
    buyFee = amount;
  }
  //SELL FEES LIMITED TO A MAXIMUM OF 1%
  function setSellFee(uint256 amount) public onlyOwner() {
    require(_amount <= 100000);
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
