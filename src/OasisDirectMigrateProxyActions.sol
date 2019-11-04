pragma solidity 0.5.11;

import {ScdMcdMigration} from "scd-mcd-migration/ScdMcdMigration.sol";
import { GemLike, JoinLike, SaiTubLike, TokenInterface, OtcInterface } from "./Interfaces.sol";
import "ds-math/math.sol";

contract OasisDirectMigrateProxyActions is DSMath {
  function sellAllAmountAndMigrateSai(
    address otc, address daiToken, uint payAmt, address buyToken, uint minBuyAmt,
    address scdMcdMigration
  ) public {
    swapSaiToDai(scdMcdMigration, payAmt);

    sellAllAmount(otc, daiToken, payAmt, buyToken, minBuyAmt);
  }

  function sellAllAmountBuyEthAndMigrateSai(
    address otc, address daiToken, uint payAmt, address wethToken, uint minBuyAmt,
    address scdMcdMigration
  ) public returns (uint wethAmt) {
    swapSaiToDai(address(scdMcdMigration), payAmt);
    
    TokenInterface(daiToken).approve(address(otc), uint256(-1));

    sellAllAmountBuyEth(OtcInterface(otc), TokenInterface(daiToken), payAmt, TokenInterface(wethToken), minBuyAmt);
  }

  function buyAllAmountAndMigrateSai(
    address otc, address buyToken, uint buyAmt, address daiToken, uint maxPayAmt,
    address scdMcdMigration
  ) public {
    uint payAmtNow = OtcInterface(otc).getPayAmount(daiToken, buyToken, buyAmt);
    require(payAmtNow <= maxPayAmt);

    swapSaiToDai(scdMcdMigration, payAmtNow);

    buyAllAmount(OtcInterface(otc), TokenInterface(buyToken), buyAmt, TokenInterface(daiToken), payAmtNow);
  }

  function buyAllAmountBuyEthAndMigrateSai(
    address otc, address wethToken, uint wethAmt, address daiToken, uint maxPayAmt,
    address scdMcdMigration
  ) public returns (uint payAmt) {
    uint payAmtNow = OtcInterface(otc).getPayAmount(daiToken, wethToken, wethAmt);
    require(payAmtNow <= maxPayAmt);

    swapSaiToDai(scdMcdMigration, payAmtNow);
    
    buyAllAmountBuyEth(OtcInterface(otc), TokenInterface(wethToken), wethAmt, TokenInterface(daiToken), payAmtNow);
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

  function sellAllAmount(address otc, address payToken, uint payAmt, address buyToken, uint minBuyAmt) private returns (uint buyAmt) {
    if (TokenInterface(payToken).allowance(address(this), address(otc)) < payAmt) {
        TokenInterface(payToken).approve(address(otc), uint(-1));
    }
    buyAmt = OtcInterface(otc).sellAllAmount(payToken, payAmt, buyToken, minBuyAmt);
    require(TokenInterface(buyToken).transfer(msg.sender, buyAmt));
  }

  function buyAllAmount(OtcInterface otc, TokenInterface buyToken, uint buyAmt, TokenInterface payToken, uint payAmtNow) private returns (uint payAmt) {
    if (payToken.allowance(address(this), address(otc)) < payAmtNow) {
        payToken.approve(address(otc), uint(-1));
    }
    payAmt = otc.buyAllAmount(address(buyToken), buyAmt, address(payToken), payAmtNow);
    require(buyToken.transfer(msg.sender, min(buyAmt, buyToken.balanceOf(address(this))))); // To avoid rounding issues we check the minimum value
  }

  function sellAllAmountBuyEth(OtcInterface otc, TokenInterface payToken, uint payAmt, TokenInterface wethToken, uint minBuyAmt
    ) private returns (uint wethAmt) {
      if (payToken.allowance(address(this), address(otc)) < payAmt) {
          payToken.approve(address(otc), uint(-1));
      }
      wethAmt = otc.sellAllAmount(address(payToken), payAmt, address(wethToken), minBuyAmt);
      withdrawAndSend(wethToken, wethAmt);
  }

  function buyAllAmountBuyEth(OtcInterface otc, TokenInterface wethToken, uint wethAmt, TokenInterface payToken, uint payAmtNow) private returns (uint payAmt) {
    if (payToken.allowance(address(this), address(otc)) < payAmtNow) {
        payToken.approve(address(otc), uint(-1));
    }
    payAmt = otc.buyAllAmount(address(wethToken), wethAmt, address(payToken), payAmtNow);
    withdrawAndSend(wethToken, wethAmt);
  }

  function withdrawAndSend(TokenInterface wethToken, uint wethAmt) private {
      wethToken.withdraw(wethAmt);
      
      (bool success,) = msg.sender.call.value(wethAmt)("");
      require(success);
  }

  // required to be able to interact with ether
  function() external payable {
  }
}