pragma solidity >= 0.6.4;

import './ownable.sol';
import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';

contract SYNStakingCotract is Owned {
  using SafeMath for uint256;

  event OpenStake(
    address account,
    uint256 synIn,
    uint256 resultingShares
  );
  event CloseStake(
    address account,
    uint256 resultingSyn,
    uint256 resultingEth
  );

  //USING TESTNET LINK AS SYN TOKEN
  IERC20 constant synToken = IERC20(0xa36085F69e2889c224210F603D836748e7dC0088);

  uint256 public totalShares;
  mapping(address => uint256) public userSYN;
  mapping(address => uint256) public userShares;

  receive() external payable {}


  function addStakingTokens(uint256 amount) public {
    uint256 sharePrice = getSharePrice();
    uint256 resultingShares = amount.mul(10**18).div(sharePrice);
    require(synToken.transferFrom(msg.sender, address(this), amount));
    totalShares = totalShares.add(resultingShares);
    userShares[msg.sender] = userShares[msg.sender].add(resultingShares);
    userSYN[msg.sender] = userSYN[msg.sender].add(amount);
    emit OpenStake(msg.sender, amount, resultingShares);
  }

  function removeStakingTokens() public {
    address payable account = msg.sender;
    require(userShares[account] > 0);
    uint256 resultingEth = userShares[account].mul(getSharePrice()).div(10**18).sub(userSYN[account]);
    uint256 resultingSyn = userSYN[msg.sender];

    totalShares = totalShares.sub(userShares[account]);

    userShares[account] = 0;
    userSYN[account] = 0;

    account.transfer(resultingEth);
    synToken.transfer(account, resultingSyn);

    emit CloseStake(msg.sender, resultingSyn, resultingEth);
  }

  function claimStakedEth() public {
    //TODO
  }
  function getSharePrice() public view returns(uint256) {
    if(totalShares == 0) {
      return(10**18);
    }
    else {
      return(address(this).balance.add(synToken.balanceOf(address(this))).mul(10**18).div(totalShares));
    }
  }

}
