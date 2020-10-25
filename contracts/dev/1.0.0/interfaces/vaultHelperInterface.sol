pragma solidity >= 0.6.6;

interface vaultHelperInterface {
  function getBonus(
    address vault,
    address token,
    uint256 eth
  )
  external
  view
  returns(
    uint256 bonus
  );
  function getPenalty(
    address vault,
    address token,
    uint256 eth
  )
  external
  view
  returns(
    uint256 penalty
  );
  function getSharePrice(
    address vault
  )
  external
  view
  returns(
    uint256 sharePrice
  );
  function getLiqAddTokens(
    address vault,
    uint256 eth
  )
  external
  view
  returns(
    uint256 rBullEquity,
    uint256 rBearEquity,
    uint256 rBullTokens,
    uint256 rBearTokens
  );
  function getLiqRemoveTokens(
    address vault,
    uint256 eth
  )
  external
  view
  returns(
    uint256 rBullEquity,
    uint256 rBearEquity,
    uint256 rBullTokens,
    uint256 rBearTokens,
    uint256 rFeesPaid
  );
}
