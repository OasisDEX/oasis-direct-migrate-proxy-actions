pragma solidity 0.5.11;

contract TokenInterface {
    function balanceOf(address) public returns (uint);
    function allowance(address, address) public returns (uint);
    function approve(address, uint) public;
    function transfer(address,uint) public returns (bool);
    function transferFrom(address, address, uint) public returns (bool);
    function deposit() public payable;
    function withdraw(uint) public;
}

contract OtcInterface {
    function sellAllAmount(address, uint, address, uint) public returns (uint);
    function buyAllAmount(address, uint, address, uint) public returns (uint);
    function getPayAmount(address, address, uint) public returns (uint);
}

contract OasisDirectProxy {
    function sellAllAmount(address otc, address payToken, uint payAmt, address buyToken, uint minBuyAmt) public returns (uint buyAmt) {}
    function buyAllAmount(address otc, address buyToken, uint buyAmt, address payToken, uint maxPayAmt) public returns (uint payAmt) {}
}

contract OasisDirectMigrateProxyActions {
  function sellAllAmountAndMigrateSai(
    address migrationProxyActions, address scdMcdMigration, address oasisDirectProxy, 
    address daiToken, address otc, uint payAmt, address buyToken, uint minBuyAmt
  ) public {
    bytes memory data = abi.encodeWithSelector(bytes4(keccak256("swapSaiToDai(address,uint256)")), address(scdMcdMigration), payAmt);
    (bool success,) = migrationProxyActions.delegatecall(data);
    require(success);
    
    TokenInterface(daiToken).approve(address(otc), uint256(-1));
    OasisDirectProxy(oasisDirectProxy).sellAllAmount(otc, daiToken, payAmt, buyToken, minBuyAmt);
  }
}