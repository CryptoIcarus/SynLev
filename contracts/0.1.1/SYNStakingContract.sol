pragma solidity >= 0.6.4;

import './ownable.sol';
import './SafeMath.sol';
import './IERC20.sol';

contract SYNStakingCotract is Owned {
  using SafeMath for uint256;

  IERC20 constant synToken = IERC20();

  uint256 public totalShares;
  mapping(address => uint256) public userSYN;
  mapping(address => uint256) public userShares;

  receive() external payable {}

  //UNTESTED
  function addStakingTokens(uint256 amount) public {
    uint256 sharePrice = getSharePrice();
    uint256 resultingShares = amount.mul(10**18).div(sharePrice);
    require(transferFrom(msg.sender, address(this), amount));
    totalShares = totalShares.add(resultingShares);
    userShares[msg.sender] = userShares[msg.sender].add(resultingShares);
    userSYN[msg.sender] = userSYN[msg.sender].add(amount);
  }
  //UNTESTED
  function removeStakingTokens() public {
    address payable account = msg.sender;
    require(userShares[account] > 0);
    uint256 sharePrice = getSharePrice();
    uint256 resultingValue = userShares[account].mul(sharePrice).div(10**18);
    uint256 resultingEth = resultingValue.sub(userSYN[account]);

    totalShares = totalShares.sub(userShares[account]);

    userSYN[account] = 0;
    userShares[account] = 0;

    transfer.account(resultingEth);
    synToken.transfer(account, userSYN[msg.sender]);
  }
  //UNTESTED
  function claimStakedEth() public {
    //TODO
  }
  function getSharePrice() public view returns(uint256) {
    if(totalLiqShares == 0) {
      return(address(this).balance);
    }
    else {
      return(address(this).balance.add(totalSYN).mul(10**18).div(totalShares));
    }
  }

}
