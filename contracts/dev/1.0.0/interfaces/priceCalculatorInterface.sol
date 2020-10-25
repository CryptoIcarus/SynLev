pragma solidity >= 0.6.6;

interface priceCalculatorInterface {
  function getKFactor(
    uint256 targetEquity,
    uint256 bullEquity,
    uint256 bearEquity,
    uint256 totalEquity
  )
  external
  view
  returns(
    uint256 kFactor
  );
  function getUpdatedPrice(
    address vault,
    uint256 roundId
  )
    external
    view
    returns(
      uint256 rBullPrice,
      uint256 rBearPrice,
      uint256 rBullLiqEquity,
      uint256 rBearLiqEquity,
      uint256 rBullEquity,
      uint256 rBearEquity,
      uint256 rRoundId,
      bool updated
    );
}
