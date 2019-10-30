pragma solidity 0.5.11;

import {ScdMcdMigration} from "scd-mcd-migration/ScdMcdMigration.sol";
import { GemLike, JoinLike, SaiTubLike, TokenInterface } from "./Interfaces.sol";

contract OasisDirectMigrateProxyActions {
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
    address scdMcdMigration, address oasisDirectProxy
  ) public {
    swapSaiToDai(address(scdMcdMigration), payAmt);
    
    TokenInterface(daiToken).approve(otc, uint256(-1));

    (bool success, bytes memory boughtAmtBytes) = oasisDirectProxy.delegatecall(
      abi.encodeWithSelector(bytes4(keccak256("sellAllAmount(address,address,uint256,address,uint256)")), otc, daiToken, payAmt, buyToken, minBuyAmt)
    );
    require(success);
    uint256 boughtAmt = abi.decode(boughtAmtBytes, (uint));

    TokenInterface(buyToken).transfer(msg.sender, boughtAmt);
  }

  function buyAllAmountAndMigrateSai(
    address otc, address buyToken, uint buyAmt, address daiToken, uint maxPayAmt,
    address scdMcdMigration, address oasisDirectProxy
  ) public {
    swapSaiToDai(scdMcdMigration, maxPayAmt);
    
    TokenInterface(daiToken).approve(otc, uint256(-1));

    (bool success, bytes memory usedDaiAmtBytes) = oasisDirectProxy.delegatecall(
      abi.encodeWithSelector(bytes4(keccak256("buyAllAmount(address,address,uint256,address,uint256)")), otc, buyToken, buyAmt, daiToken, maxPayAmt)
    );
    require(success);
    uint256 usedDaiAmt = abi.decode(usedDaiAmtBytes, (uint));
    uint256 unusedDaiAmt = maxPayAmt - usedDaiAmt;
    // this will send back any leftover dai
    // @todo use min?
    if (unusedDaiAmt > 0) {
      swapDaiToSai(scdMcdMigration, unusedDaiAmt);
    }

    TokenInterface(buyToken).transfer(msg.sender, buyAmt);
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
}