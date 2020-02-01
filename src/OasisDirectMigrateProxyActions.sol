pragma solidity ^0.5.12;

import { JoinLike, SaiTubLike, GemLike, OtcLike, ScdMcdMigrationLike } from "./Interfaces.sol";
import "ds-math/math.sol";

contract OasisDirectMigrateProxyActions is DSMath {
    function sellAllAmountAndMigrateSai(
        address otc,
        address daiToken,
        uint daiAmt,
        address buyToken,
        uint minBuyAmt,
        address scdMcdMigration
    ) public returns (uint buyAmt) {
        swapSaiToDai(scdMcdMigration, daiAmt);

        if (GemLike(daiToken).allowance(address(this), otc) < daiAmt) {
            GemLike(daiToken).approve(otc, uint(-1));
        }
        buyAmt = OtcLike(otc).sellAllAmount(daiToken, daiAmt, buyToken, minBuyAmt);
        require(GemLike(buyToken).transfer(msg.sender, buyAmt), "");
    }

    function sellAllAmountBuyEthAndMigrateSai(
        address otc,
        address daiToken,
        uint daiAmt,
        address wethToken,
        uint minBuyAmt,
        address scdMcdMigration
    ) public returns (uint wethAmt) {
        swapSaiToDai(scdMcdMigration, daiAmt);

        if (GemLike(daiToken).allowance(address(this), otc) < daiAmt) {
            GemLike(daiToken).approve(otc, uint(-1));
        }
        wethAmt = OtcLike(otc).sellAllAmount(daiToken, daiAmt, wethToken, minBuyAmt);
        withdrawAndSend(wethToken, wethAmt);
    }

    function buyAllAmountAndMigrateSai(
        address otc,
        address buyToken,
        uint buyAmt,
        address daiToken,
        uint maxDaiAmt,
        address scdMcdMigration
    ) public returns (uint payAmt) {
        uint daiAmtNow = OtcLike(otc).getPayAmount(daiToken, buyToken, buyAmt);
        require(daiAmtNow <= maxDaiAmt, "");

        swapSaiToDai(scdMcdMigration, daiAmtNow);

        if (GemLike(daiToken).allowance(address(this), otc) < daiAmtNow) {
            GemLike(daiToken).approve(otc, uint(-1));
        }
        payAmt = OtcLike(otc).buyAllAmount(address(buyToken), buyAmt, daiToken, daiAmtNow);
        require(
            GemLike(buyToken).transfer(msg.sender, min(buyAmt, GemLike(buyToken).balanceOf(address(this)))),
            ""
        ); // To avoid rounding issues we check the minimum value
    }

    function buyAllAmountBuyEthAndMigrateSai(
        address otc,
        address wethToken,
        uint wethAmt,
        address daiToken,
        uint maxDaiAmt,
        address scdMcdMigration
    ) public returns (uint payAmt) {
        uint daiAmtNow = OtcLike(otc).getPayAmount(daiToken, wethToken, wethAmt);
        require(daiAmtNow <= maxDaiAmt, "");

        swapSaiToDai(scdMcdMigration, daiAmtNow);

        if (GemLike(daiToken).allowance(address(this), otc) < daiAmtNow) {
            GemLike(daiToken).approve(otc, uint(-1));
        }
        payAmt = OtcLike(otc).buyAllAmount(wethToken, wethAmt, daiToken, daiAmtNow);
        withdrawAndSend(wethToken, wethAmt);
    }

    // private methods
    function swapSaiToDai(address scdMcdMigration, uint wad) private {
        GemLike sai = ScdMcdMigrationLike(scdMcdMigration).tub().sai();
        sai.transferFrom(msg.sender, address(this), wad);
        if (sai.allowance(address(this), scdMcdMigration) < wad) {
            sai.approve(scdMcdMigration, wad);
        }
        ScdMcdMigrationLike(scdMcdMigration).swapSaiToDai(wad);
    }

    function withdrawAndSend(address wethToken, uint wethAmt) private {
        GemLike(wethToken).withdraw(wethAmt);

        (bool success,) = msg.sender.call.value(wethAmt)("");
        require(success, "");
    }

    // required to be able to interact with ether
    function() external payable { }
}