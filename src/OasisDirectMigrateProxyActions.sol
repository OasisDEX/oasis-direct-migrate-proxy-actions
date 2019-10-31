pragma solidity 0.5.11;

import {ScdMcdMigration} from "scd-mcd-migration/ScdMcdMigration.sol";
import { GemLike, JoinLike, SaiTubLike, TokenInterface, OtcInterface } from "./Interfaces.sol";
import "ds-math/math.sol";

contract OasisDirectMigrateProxyActions is DSMath {
  event logs                   (bytes);
  event log_bytes32            (bytes32);
  event log_named_address      (bytes32 key, address val);
  event log_named_bytes32      (bytes32 key, bytes32 val);
  event log_named_decimal_int  (bytes32 key, int val, uint decimals);
  event log_named_decimal_uint (bytes32 key, uint val, uint decimals);
  event log_named_int          (bytes32 key, int val);
  event log_named_uint         (bytes32 key, uint val);

  function sellAllAmountAndMigrateSai(
    address otc, address daiToken, uint payAmt, address buyToken, uint minBuyAmt,
    address scdMcdMigration
  ) public {
    swapSaiToDai(scdMcdMigration, payAmt);

    sellAllAmount(otc, daiToken, payAmt, buyToken, minBuyAmt);
  }

  function sellAllAmountBuyEthAndMigrateSai(
    address otc, address payToken, uint payAmt, address wethToken, uint minBuyAmt,
    address scdMcdMigration, address oasisDirectProxy
  ) public returns (uint wethAmt) {
    // swapSaiToDai(address(scdMcdMigration), payAmt);
    
    // TokenInterface(daiToken).approve(otc, uint256(-1));

    // (bool success, bytes memory boughtAmtBytes) = oasisDirectProxy.delegatecall(
    //   abi.encodeWithSelector(bytes4(keccak256("sellAllAmountEth(address,address,uint256,address,uint256)")), otc, daiToken, payAmt, buyToken, minBuyAmt)
    // );
    // require(success);
    // uint256 boughtAmt = abi.decode(boughtAmtBytes, (uint));

    // // pass ether
    // require(msg.sender.call.value(wethAmt)());
  }


  function buyAllAmountAndMigrateSai(
    address otc, address buyToken, uint buyAmt, address daiToken, uint maxPayAmt,
    address scdMcdMigration
  ) public {
    swapSaiToDai(scdMcdMigration, maxPayAmt);

    emit log_named_uint("DAI:", TokenInterface(daiToken).balanceOf(address(this)));
    
    uint256 usedDaiAmt = buyAllAmount(OtcInterface(otc), TokenInterface(buyToken), buyAmt, TokenInterface(daiToken), maxPayAmt);
    uint256 unusedDaiAmt = maxPayAmt - usedDaiAmt;
    // this will send back any leftover dai
    // @todo use min?
    if (unusedDaiAmt > 0) {
      swapDaiToSai(scdMcdMigration, unusedDaiAmt);
    }
  }
  // @todo real proxy impl

// @todo reduce repetition
  function buyAllAmountBuyEth(
    address otc, address wethToken, uint wethAmt, address payToken, uint maxPayAmt,
    address scdMcdMigration, address oasisDirectProxy
  ) public returns (uint payAmt) {
    // swapSaiToDai(scdMcdMigration, maxPayAmt);
    
    // TokenInterface(daiToken).approve(otc, uint256(-1));

    // (bool success, bytes memory usedDaiAmtBytes) = oasisDirectProxy.delegatecall(
    //   abi.encodeWithSelector(bytes4(keccak256("buyAllAmount(address,address,uint256,address,uint256)")), otc, buyToken, buyAmt, daiToken, maxPayAmt)
    // );
    // require(success);
    // uint256 usedDaiAmt = abi.decode(usedDaiAmtBytes, (uint));
    // uint256 unusedDaiAmt = maxPayAmt - usedDaiAmt;
    // // this will send back any leftover dai
    // // @todo use min?
    // if (unusedDaiAmt > 0) {
    //   swapDaiToSai(scdMcdMigration, unusedDaiAmt);
    // }

    // // pass ether
    // require(msg.sender.call.value(wethAmt)());
  }

  function swapSaiToDai(
        address scdMcdMigration,    // Migration contract address
        uint wad                            // Amount to swap
  ) private {
      GemLike sai = SaiTubLike(address(ScdMcdMigration(scdMcdMigration).tub())).sai();
      GemLike dai = JoinLike(address(ScdMcdMigration(scdMcdMigration).daiJoin())).dai();
      sai.transferFrom(msg.sender, address(this), wad);
      if (sai.allowance(address(this), scdMcdMigration) < wad) {
          sai.approve(scdMcdMigration, wad);
      }
      ScdMcdMigration(scdMcdMigration).swapSaiToDai(wad);
  }

  function swapDaiToSai(
      address scdMcdMigration,    // Migration contract address
      uint wad                            // Amount to swap
  ) private {
      GemLike sai = SaiTubLike(address(ScdMcdMigration(scdMcdMigration).tub())).sai();
      GemLike dai = JoinLike(address(ScdMcdMigration(scdMcdMigration).daiJoin())).dai();
      dai.transferFrom(msg.sender, address(this), wad);
      if (dai.allowance(address(this), scdMcdMigration) < wad) {
          dai.approve(scdMcdMigration, wad);
      }
      ScdMcdMigration(scdMcdMigration).swapDaiToSai(wad);
      sai.transfer(msg.sender, wad);
  }

  function sellAllAmount(address otc, address payToken, uint payAmt, address buyToken, uint minBuyAmt) private returns (uint buyAmt) {
    if (TokenInterface(payToken).allowance(address(this), address(otc)) < payAmt) {
        TokenInterface(payToken).approve(address(otc), uint(-1));
    }
    buyAmt = OtcInterface(otc).sellAllAmount(payToken, payAmt, buyToken, minBuyAmt);
    require(TokenInterface(buyToken).transfer(msg.sender, buyAmt));
  }

  function buyAllAmount(OtcInterface otc, TokenInterface buyToken, uint buyAmt, TokenInterface payToken, uint maxPayAmt) public returns (uint payAmt) {
    uint payAmtNow = otc.getPayAmount(address(payToken), address(buyToken), buyAmt);
    require(payAmtNow <= maxPayAmt);
    if (payToken.allowance(address(this), address(otc)) < payAmtNow) {
        payToken.approve(address(otc), uint(-1));
    }
    payAmt = otc.buyAllAmount(address(buyToken), buyAmt, address(payToken), payAmtNow);
    require(buyToken.transfer(msg.sender, min(buyAmt, buyToken.balanceOf(address(this))))); // To avoid rounding issues we check the minimum value
    }
}