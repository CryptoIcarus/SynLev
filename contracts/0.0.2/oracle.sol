//////////////////////////////////////////////////
//SYNLEV ORACLE CONTRACT V 0.0.2
//////////////////////////



pragma solidity >= 0.6.4;

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


interface AggregatorInterface {
  function latestAnswer() external view returns (int256);
  function latestTimestamp() external view returns (uint256);
  function latestRound() external view returns (uint256);
  function getAnswer(uint256 roundId) external view returns (int256);
  function getTimestamp(uint256 roundId) external view returns (uint256);

  event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 timestamp);
  event NewRound(uint256 indexed roundId, address indexed startedBy, uint256 startedAt);

  function decimals() external view returns (uint8);
  function description() external view returns (string memory);
  function getRoundData(uint256 _roundId)
    external
    view
    returns (
      uint256 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint256 answeredInRound
    );
  function latestRoundData()
    external
    view
    returns (
      uint256 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint256 answeredInRound
    );
  function version() external view returns (uint256);
}

interface VaultInterface {
    function getLatestRoundId() external view returns(uint256);
}


contract proxy is Context, Owned {
  using SafeMath for uint256;

  constructor() public {
    ref = AggregatorInterface(0x8468b2bDCE073A157E560AA4D9CcF6dB1DB98507);
  }



  function getPriceData() public view returns (uint256[] memory, uint256) {
      VaultInterface _vault = VaultInterface(msg.sender);
      uint256 _lastPriceRound = _vault.getLatestRoundId();
      uint256 _latestRound = ref.latestRound();
      uint256[] memory _pricearray;
      if(_latestRound > _lastPriceRound + 5) {
         _pricearray = new uint256[] (5);
         _pricearray[0] = uint256(ref.getAnswer(_lastPriceRound));
         for(uint i = 0; i < 4; i++) {
              _pricearray[i] = uint256(ref.getAnswer(_latestRound - i));
          }
         return(_pricearray, _latestRound);
      }
      else if(_latestRound > _lastPriceRound) {
        _pricearray = new uint256[] (1 + _latestRound - _lastPriceRound);
          for(uint i = 0; i < 10; i++) {
              _pricearray[i] = uint256(ref.getAnswer(_lastPriceRound + i));
          }
        return(_pricearray, _latestRound);
      }
      else {
          return(new uint256[](0), _latestRound);
      }

  }

  function getPriceArrayUint() public view returns (uint256[] memory, uint256) {
      uint256 _latestRound = ref.latestRound();
      uint256[] memory _pricearray = new uint256[] (10);
      for(uint i = 0; i < 10; i++) {
          _pricearray[i] = uint256(ref.getAnswer(_latestRound - 9 + i));
      }
      return(_pricearray, ref.latestRound());
  }

  function getUintAnswer(uint256 roundId) public view returns(uint256) {
      return uint256(ref.getAnswer(roundId));
  }


  function getLatestAnswer() public view returns (int256) {
    return ref.latestAnswer();
  }
  function getAnswerId(uint256 roundId) public view returns (int256) {
    return ref.getAnswer(roundId);
  }


  function getLatestTimestamp() public view returns (uint256) {
    return ref.latestTimestamp();
  }

  function getPreviousAnswer(uint256 _back) public view returns (int256) {
    uint256 latest = ref.latestRound();
    require(_back <= latest, "Not enough history");
    return ref.getAnswer(latest - _back);
  }

  function getPreviousTimestamp(uint256 _back) public view returns (uint256) {
    uint256 latest = ref.latestRound();
    require(_back <= latest, "Not enough history");
    return ref.getTimestamp(latest - _back);
  }


  AggregatorInterface internal ref;


  function setReferenceContract(address _aggregator) public onlyOwner() {
    ref = AggregatorInterface(_aggregator);
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
