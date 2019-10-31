pragma solidity ^0.5.11;

import "ds-math/math.sol";

contract OtcInterface {
    function sellAllAmount(address, uint, address, uint) public returns (uint);
    function buyAllAmount(address, uint, address, uint) public returns (uint);
    function getPayAmount(address, address, uint) public returns (uint);
}

contract TokenInterface {
    function balanceOf(address) public returns (uint);
    function allowance(address, address) public returns (uint);
    function approve(address, uint) public;
    function transfer(address,uint) public returns (bool);
    function transferFrom(address, address, uint) public returns (bool);
    function deposit() public payable;
    function withdraw(uint) public;
}

contract OasisDirectProxy is DSMath {
    function withdrawAndSend(TokenInterface wethToken, uint wethAmt) internal {
        wethToken.withdraw(wethAmt);
        
        (bool success,) = msg.sender.call.value(wethAmt)("");
        require(success);
    }

    function sellAllAmount(OtcInterface otc, TokenInterface payToken, uint payAmt, TokenInterface buyToken, uint minBuyAmt) public returns (uint buyAmt) {
        require(payToken.transferFrom(msg.sender, address(this), payAmt));
        if (payToken.allowance(address(this), address(otc)) < payAmt) {
            payToken.approve(address(otc), uint(-1));
        }
        buyAmt = otc.sellAllAmount(address(payToken), payAmt, address(buyToken), minBuyAmt);
        require(buyToken.transfer(msg.sender, buyAmt));
    }

    function sellAllAmountBuyEth(OtcInterface otc, TokenInterface payToken, uint payAmt, TokenInterface wethToken, uint minBuyAmt) public returns (uint wethAmt) {
        require(payToken.transferFrom(msg.sender, address(this), payAmt));
        if (payToken.allowance(address(this), address(otc)) < payAmt) {
            payToken.approve(address(otc), uint(-1));
        }
        wethAmt = otc.sellAllAmount(address(payToken), payAmt, address(wethToken), minBuyAmt);
        withdrawAndSend(wethToken, wethAmt);
    }

    function buyAllAmount(OtcInterface otc, TokenInterface buyToken, uint buyAmt, TokenInterface payToken, uint maxPayAmt) public returns (uint payAmt) {
        uint payAmtNow = otc.getPayAmount(address(payToken), address(buyToken), buyAmt);
        require(payAmtNow <= maxPayAmt);
        require(payToken.transferFrom(msg.sender, address(this), payAmtNow));
        if (payToken.allowance(address(this), address(otc)) < payAmtNow) {
            payToken.approve(address(otc), uint(-1));
        }
        payAmt = otc.buyAllAmount(address(buyToken), buyAmt, address(payToken), payAmtNow);
        require(buyToken.transfer(msg.sender, min(buyAmt, buyToken.balanceOf(address(this))))); // To avoid rounding issues we check the minimum value
    }

    function buyAllAmountBuyEth(OtcInterface otc, TokenInterface wethToken, uint wethAmt, TokenInterface payToken, uint maxPayAmt) public returns (uint payAmt) {
        uint payAmtNow = otc.getPayAmount(address(payToken), address(wethToken), wethAmt);
        require(payAmtNow <= maxPayAmt);
        require(payToken.transferFrom(msg.sender, address(this), payAmtNow));
        if (payToken.allowance(address(this), address(otc)) < payAmtNow) {
            payToken.approve(address(otc), uint(-1));
        }
        payAmt = otc.buyAllAmount(address(wethToken), wethAmt, address(payToken), payAmtNow);
        withdrawAndSend(wethToken, wethAmt);
    }
}